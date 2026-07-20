import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact_match.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/chat_realtime_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/deep_link_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/offline_queue_service.dart';
import '../../../core/widgets/full_screen_image_avatar.dart';
import '../../../core/widgets/full_screen_image_view.dart';
import '../../../core/services/native_app_picker.dart';
import '../../../core/widgets/whatsapp_gallery_sheet.dart';
import '../../../core/widgets/file_preview_sheet.dart';
import '../../../core/widgets/dwelly_orbiting_loader.dart';
import '../../../core/services/contact_service.dart';
import '../../user_profile/presentation/user_public_profile_page.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';
import 'dart:convert';
import '../../helper/presentation/helper_profile_page.dart';
import 'dart:math' as math;

class ChatPage extends StatefulWidget {
  final Rental rental;
  final Conversation? existingConversation;

  const ChatPage({super.key, required this.rental, this.existingConversation});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _realtimeService = ChatRealtimeService();
  final _uuid = const Uuid();
  List<ChatMessage> _messages = [];
  Conversation? _conversation;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRealtimeConnected = false;
  String? _error;
  Timer? _pollingTimer;
  void Function()? _conversationUnsubscribe;
  void Function()? _statusUnsubscribe;
  void Function()? _typingUnsubscribe;
  void Function()? _readReceiptUnsubscribe;
  StreamSubscription<String>? _offlineQueueSubscription;
  ChatSafetyStatus _chatSafety = const ChatSafetyStatus.none();
  
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;
  Timer? _otherUserTypingTimer;

  bool _isEmojiPickerVisible = false;
  final FocusNode _focusNode = FocusNode();

  // Pagination state
  int _currentPage = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  static const int _messagesPerPage = 20;

  int get _otherUserId {
    final currentUserId = AuthService.currentUser?.id;
    if (_conversation != null) {
      return currentUserId == _conversation!.ownerId
          ? _conversation!.userId
          : _conversation!.ownerId;
    }
    return widget.rental.ownerId ?? 0;
  }

  String get _otherUserName {
    final currentUserId = AuthService.currentUser?.id;
    if (_conversation != null) {
      if (currentUserId == _conversation!.ownerId) {
        return _conversation!.userName;
      } else {
        return _conversation!.ownerName;
      }
    }
    return widget.rental.ownerName ?? 'Owner';
  }

  String? get _otherUserUsername {
    final currentUserId = AuthService.currentUser?.id;
    if (_conversation != null) {
      if (currentUserId == _conversation!.ownerId) {
        return _conversation!.userUsername;
      } else {
        return _conversation!.ownerUsername;
      }
    }
    return null;
  }

  String? get _otherUserAvatarUrl {
    final currentUserId = AuthService.currentUser?.id;
    String? avatar;

    if (_conversation != null) {
      if (currentUserId == _conversation!.ownerId) {
        avatar = _conversation!.userAvatarUrl;
      } else {
        avatar = _conversation!.ownerAvatarUrl;
      }
    }

    if (avatar == null || avatar.isEmpty) {
      avatar = widget.rental.ownerAvatarUrl;
    }

    if (avatar == null || avatar.isEmpty) {
      try {
        final contact = ContactService.contacts.value.firstWhere(
          (c) => c.contactUserId == _otherUserId,
        );
        avatar = contact.avatarUrl;
      } catch (_) {}
    }

    return avatar;
  }

  void _showSaveContactDialog(
    BuildContext context,
    int userId,
    String currentName,
    String? username,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Contact'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Contact Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await ContactService.saveContact(
                  userId: userId,
                  customName: newName,
                  username: username,
                );
                if (mounted) {
                  setState(() {});
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Conversation _withSafety(Conversation source, ChatSafetyStatus status) {
    return Conversation(
      id: source.id,
      listingType: source.listingType,
      listingId: source.listingId,
      listingTitle: source.listingTitle,
      listingImageUrl: source.listingImageUrl,
      rentalId: source.rentalId,
      rentalTitle: source.rentalTitle,
      userId: source.userId,
      userName: source.userName,
      ownerId: source.ownerId,
      ownerName: source.ownerName,
      mutedByMe: status.mutedByMe,
      blockedByMe: status.blockedByMe,
      blockedMe: status.blockedMe,
      lastMessage: source.lastMessage,
      lastMessageAt: source.lastMessageAt,
      unreadCount: source.unreadCount,
      createdAt: source.createdAt,
    );
  }

  void _applySafetyStatus(ChatSafetyStatus status) {
    if (!mounted) return;
    setState(() {
      _chatSafety = status;
      final currentConversation = _conversation;
      if (currentConversation != null) {
        _conversation = _withSafety(currentConversation, status);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isEmojiPickerVisible) {
        setState(() {
          _isEmojiPickerVisible = false;
        });
      }
    });
    NotificationService.clearMessageNotifications(
      conversationId: widget.existingConversation?.id,
    );
    _conversation = widget.existingConversation;
    if (_conversation != null) {
      _chatSafety = ChatSafetyStatus(
        mutedByMe: _conversation!.mutedByMe,
        blockedByMe: _conversation!.blockedByMe,
        blockedMe: _conversation!.blockedMe,
      );
    }
    _scrollController.addListener(_onScroll);
    _connectRealtime();
    if (_conversation != null) {
      _loadMessages();
      _startPolling();
      _subscribeConversationChannel();
      unawaited(_refreshChatSafetyStatus());
    } else {
      _isLoading = false;
    }

    _offlineQueueSubscription = OfflineQueueService.onMessageSent.listen((
      clientMessageId,
    ) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere(
          (m) => m.clientMessageId == clientMessageId,
        );
        if (index >= 0) {
          final m = _messages[index];
          _messages[index] = ChatMessage(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            senderName: m.senderName,
            clientMessageId: m.clientMessageId,
            content: m.content,
            messageType: m.messageType,
            mediaUrl: m.mediaUrl,
            localPath: m.localPath,
            createdAt: m.createdAt,
            isRead: m.isRead,
            deliveryStatus: 'sent',
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _offlineQueueSubscription?.cancel();
    _pollingTimer?.cancel();
    _conversationUnsubscribe?.call();
    _statusUnsubscribe?.call();
    _realtimeService.disconnect();
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load more when scrolled to top
    if (_scrollController.position.pixels <= 150 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        !_isLoading) {
      _loadMoreMessages();
    }
  }

  void _startPolling() {
    // Poll fallback when live socket is unavailable.
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _pollForNewMessages();
    });
  }

  Future<void> _pollForNewMessages() async {
    if (_conversation == null ||
        _isLoading ||
        _isSending ||
        _isRealtimeConnected) {
      return;
    }

    try {
      final result = await ChatService.getMessagesPaginated(
        _conversation!.id!,
        page: 0,
        limit: _messagesPerPage,
      );
      final latestMessages = List<ChatMessage>.from(result['messages'] ?? []);
      if (latestMessages.isEmpty) return;

      await _restoreLocalPaths(latestMessages);
      final existingIds = _messages.map((m) => m.id).toSet();
      final existingClientIds = _messages
          .where(
            (m) => m.clientMessageId != null && m.clientMessageId!.isNotEmpty,
          )
          .map((m) => m.clientMessageId)
          .toSet();
      final newMessages = latestMessages
          .where(
            (message) =>
                !existingIds.contains(message.id) &&
                !existingClientIds.contains(message.clientMessageId),
          )
          .toList();

      if (newMessages.isNotEmpty) {
        final wasAtBottom =
            _scrollController.hasClients &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 100;
        setState(() {
          _messages = [..._messages, ...newMessages]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        // Auto-scroll if user was already at the bottom
        if (wasAtBottom) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  Future<void> _connectRealtime() async {
    final currentUserId = AuthService.currentUser?.id;
    if (currentUserId == null) return;

    await _realtimeService.connect(
      onConnected: () {
        if (!mounted) return;
        setState(() => _isRealtimeConnected = true);
        
        _statusUnsubscribe?.call();
        _statusUnsubscribe = _realtimeService.subscribeUserMessageStatus(
          currentUserId,
          _onMessageStatusEvent,
        );
        
        _typingUnsubscribe?.call();
        _typingUnsubscribe = _realtimeService.subscribeUserTyping(
          currentUserId,
          _onTypingEvent,
        );

        _readReceiptUnsubscribe?.call();
        _readReceiptUnsubscribe = _realtimeService.subscribeUserReadReceipts(
          currentUserId,
          _onReadReceiptEvent,
        );
        
        _subscribeConversationChannel();
        
        if (_conversation?.id != null) {
          _realtimeService.sendReadReceiptEvent(_conversation!.id!);
        }

        // Thundering herd protection: check if reconnecting after a significant drop (>= 5s)
        final lastDisconnect = _realtimeService.lastDisconnectedAt;
        _realtimeService.clearDisconnectTimestamp();
        if (lastDisconnect != null &&
            DateTime.now().difference(lastDisconnect).inSeconds >= 5) {
          // Add query smoothing jitter (0-1.5s) before catch-up REST sync
          Future.delayed(Duration(milliseconds: Random().nextInt(1500)), () {
            if (mounted && _isRealtimeConnected) {
              _pollForNewMessages();
            }
          });
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isRealtimeConnected = false);
      },
    );
  }

  void _onTypingEvent(TypingEvent event) {
    if (!mounted) return;
    if (_conversation != null && event.conversationId == _conversation!.id) {
      setState(() {
        _isOtherUserTyping = event.isTyping;
      });
      _otherUserTypingTimer?.cancel();
      if (event.isTyping) {
        _otherUserTypingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() => _isOtherUserTyping = false);
          }
        });
      }
    }
  }

  void _onReadReceiptEvent(ReadReceiptEvent event) {
    if (!mounted) return;
    if (_conversation != null && event.conversationId == _conversation!.id) {
      setState(() {
        for (var msg in _messages) {
          if (msg.senderId != event.readByUserId) {
            msg.isRead = true;
          }
        }
      });
    }
  }

  void _subscribeConversationChannel() {
    final conversationId = _conversation?.id;
    if (conversationId == null) return;
    _conversationUnsubscribe?.call();
    _conversationUnsubscribe = _realtimeService.subscribeConversation(
      conversationId,
      _onRealtimeMessage,
    );
  }

  void _onRealtimeMessage(ChatMessage incoming) {
    if (!mounted) return;
    setState(() {
      final indexById = incoming.id != null
          ? _messages.indexWhere((m) => m.id == incoming.id)
          : -1;
      final indexByClientId =
          incoming.clientMessageId != null &&
              incoming.clientMessageId!.isNotEmpty
          ? _messages.indexWhere(
              (m) => m.clientMessageId == incoming.clientMessageId,
            )
          : -1;

      if (indexById >= 0) {
        _messages[indexById] = incoming;
      } else if (indexByClientId >= 0) {
        _messages[indexByClientId] = incoming;
      } else {
        _messages.add(incoming);
      }
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    if (_conversation != null &&
        _conversation!.id != null &&
        incoming.senderId != AuthService.currentUser?.id) {
      unawaited(ChatService.markConversationAsRead(_conversation!.id!));
      _realtimeService.sendReadReceiptEvent(_conversation!.id!);
    }
    _scrollToBottom();
  }

  void _onMessageStatusEvent(MessageStatusEvent event) {
    if (!mounted) return;
    final conversationId = _conversation?.id;
    if (conversationId == null || event.conversationId != conversationId) {
      return;
    }

    setState(() {
      final status = event.status.toUpperCase();
      final index = event.clientMessageId == null
          ? -1
          : _messages.indexWhere(
              (m) => m.clientMessageId == event.clientMessageId,
            );

      if (status == 'SENT' && event.message != null) {
        if (index >= 0) {
          _messages[index] = event.message!;
        } else {
          _messages.add(event.message!);
        }
      } else if (status == 'WARNING' && event.message != null) {
        final warningIndexById = event.message!.id == null
            ? -1
            : _messages.indexWhere((m) => m.id == event.message!.id);
        if (warningIndexById >= 0) {
          _messages[warningIndexById] = event.message!;
        } else {
          _messages.add(event.message!);
        }
      } else if (status == 'FAILED' && index >= 0) {
        final failed = _messages[index];
        _messages[index] = ChatMessage(
          id: failed.id,
          conversationId: failed.conversationId,
          senderId: failed.senderId,
          senderName: failed.senderName,
          clientMessageId: failed.clientMessageId,
          content: failed.content,
          messageType: failed.messageType,
          mediaUrl: failed.mediaUrl,
          localPath: failed.localPath,
          createdAt: failed.createdAt,
          isRead: failed.isRead,
          deliveryStatus: 'failed',
        );
      }
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });

    if (event.message != null &&
        (event.status.toUpperCase() == 'SENT' ||
            event.status.toUpperCase() == 'WARNING')) {
      _scrollToBottom();
    }
  }

  int? _activeConversationId() {
    final id = _conversation?.id;
    if (id == null || id <= 0) return null;
    return id;
  }

  int? _resolveCounterpartUserId() {
    final currentUserId = AuthService.currentUser?.id;
    final conversation = _conversation;
    if (conversation != null) {
      final conversationUserId = conversation.userId > 0
          ? conversation.userId
          : null;
      final conversationOwnerId = conversation.ownerId > 0
          ? conversation.ownerId
          : null;

      if (currentUserId != null) {
        if (conversationUserId == currentUserId &&
            conversationOwnerId != null) {
          return conversationOwnerId;
        }
        if (conversationOwnerId == currentUserId &&
            conversationUserId != null) {
          return conversationUserId;
        }
      }

      if (conversationOwnerId != null && conversationOwnerId != currentUserId) {
        return conversationOwnerId;
      }
      if (conversationUserId != null && conversationUserId != currentUserId) {
        return conversationUserId;
      }
    }

    final rentalOwnerId = widget.rental.ownerId;
    if (rentalOwnerId != null &&
        rentalOwnerId > 0 &&
        rentalOwnerId != currentUserId) {
      return rentalOwnerId;
    }
    return null;
  }

  Future<void> _refreshChatSafetyStatus() async {
    try {
      final conversationId = _activeConversationId();
      if (conversationId != null) {
        final status = await ChatService.getConversationSafetyStatus(
          conversationId,
        );
        _applySafetyStatus(status);
        return;
      }
      final counterpartUserId = _resolveCounterpartUserId();
      if (counterpartUserId == null || counterpartUserId <= 0) return;
      final status = await ChatService.getContactSafetyStatus(
        counterpartUserId,
      );
      _applySafetyStatus(status);
    } catch (_) {
      // Best effort. Chat must remain usable even if safety status fetch fails.
    }
  }

  Future<void> _toggleMute() async {
    final previous = _chatSafety;
    _applySafetyStatus(
      ChatSafetyStatus(
        mutedByMe: !previous.mutedByMe,
        blockedByMe: previous.blockedByMe,
        blockedMe: previous.blockedMe,
      ),
    );

    final conversationId = _activeConversationId();
    final counterpartUserId = _resolveCounterpartUserId();
    if (conversationId == null &&
        (counterpartUserId == null || counterpartUserId <= 0)) {
      _applySafetyStatus(previous);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open the conversation first to update contact safety.',
          ),
        ),
      );
      return;
    }

    try {
      final status = conversationId != null
          ? await ChatService.updateConversationSafety(
              conversationId,
              muted: !previous.mutedByMe,
            )
          : await ChatService.updateContactSafety(
              counterpartUserId!,
              muted: !previous.mutedByMe,
            );
      _applySafetyStatus(status);
      _invalidateListingsCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.mutedByMe
                ? 'Notifications muted for this contact.'
                : 'Notifications unmuted for this contact.',
          ),
        ),
      );
    } catch (e) {
      _applySafetyStatus(previous);
      if (!mounted || isSilentError(e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              e,
              fallbackMessage: 'Failed to update mute settings.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleBlock() async {
    final currentlyBlocked = _chatSafety.blockedByMe;
    if (!currentlyBlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block contact?'),
          content: const Text(
            'Blocking prevents both of you from sending messages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final previous = _chatSafety;
    _applySafetyStatus(
      ChatSafetyStatus(
        mutedByMe: previous.mutedByMe,
        blockedByMe: !currentlyBlocked,
        blockedMe: previous.blockedMe,
      ),
    );

    final conversationId = _activeConversationId();
    final counterpartUserId = _resolveCounterpartUserId();
    if (conversationId == null &&
        (counterpartUserId == null || counterpartUserId <= 0)) {
      _applySafetyStatus(previous);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open the conversation first to update contact safety.',
          ),
        ),
      );
      return;
    }

    try {
      final status = conversationId != null
          ? await ChatService.updateConversationSafety(
              conversationId,
              blocked: !currentlyBlocked,
            )
          : await ChatService.updateContactSafety(
              counterpartUserId!,
              blocked: !currentlyBlocked,
            );
      _applySafetyStatus(status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.blockedByMe
                ? 'Contact blocked. Messaging is disabled.'
                : 'Contact unblocked.',
          ),
        ),
      );
    } catch (e) {
      _applySafetyStatus(previous);
      if (!mounted || isSilentError(e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              e,
              fallbackMessage: 'Failed to update block settings.',
            ),
          ),
        ),
      );
    }
  }

  void _invalidateListingsCache() {
    ChatService.invalidateListingVisibilityCaches();
  }

  Future<void> _loadMessages() async {
    if (_conversation == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
      _hasMoreMessages = true;
    });

    try {
      final result = await ChatService.getMessagesPaginated(
        _conversation!.id!,
        page: 0,
        limit: _messagesPerPage,
      );
      final messages = List<ChatMessage>.from(result['messages'] ?? []);
      final hasMore = result['hasMore'] == true;

      // Restore local paths for downloaded videos
      await _restoreLocalPaths(messages);

      unawaited(ChatService.markConversationAsRead(_conversation!.id!));
      _realtimeService.sendReadReceiptEvent(_conversation!.id!);

      final localUnsynced = _messages
          .where((m) => m.isLocalPending || m.isFailed)
          .toList();
      setState(() {
        _messages = [...messages];
        for (final pending in localUnsynced) {
          final exists = _messages.any(
            (m) =>
                (pending.id != null && m.id == pending.id) ||
                (pending.clientMessageId != null &&
                    pending.clientMessageId == m.clientMessageId),
          );
          if (!exists) {
            _messages.add(pending);
          }
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMoreMessages = hasMore;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load messages.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_conversation == null || _isLoadingMore || !_hasMoreMessages) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    final previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final previousMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    try {
      final nextPage = _currentPage + 1;
      final result = await ChatService.getMessagesPaginated(
        _conversation!.id!,
        page: nextPage,
        limit: _messagesPerPage,
      );
      final olderMessages = List<ChatMessage>.from(result['messages'] ?? []);
      final hasMore = result['hasMore'] == true;

      await _restoreLocalPaths(olderMessages);

      setState(() {
        final existingIds = _messages.map((m) => m.id).whereType<int>().toSet();
        final uniqueOlder = olderMessages
            .where((m) => m.id == null || !existingIds.contains(m.id))
            .toList();
        _messages = [...uniqueOlder, ..._messages];
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _currentPage = nextPage;
        _hasMoreMessages = hasMore;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;

        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - previousMaxExtent;
        _scrollController.jumpTo(previousOffset + delta);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load more messages: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _restoreLocalPaths(List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    for (final msg in messages) {
      if (msg.isVideo && msg.id != null) {
        final localPath = prefs.getString('video_local_${msg.id}');
        if (localPath != null && File(localPath).existsSync()) {
          msg.localPath = localPath;
        }
      }
    }
  }

  Future<void> _sendMessage({
    String content = '',
    String messageType = 'TEXT',
    String? mediaUrl,
  }) async {
    final text = content.isEmpty ? _messageController.text.trim() : content;
    if (text.isEmpty && mediaUrl == null) return;
    if (_chatSafety.blockedByMe || _chatSafety.blockedMe) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Messaging is disabled because this contact is blocked.',
          ),
        ),
      );
      return;
    }

    final clientMessageId = _uuid.v4();
    final pendingMessage = ChatMessage(
      conversationId: _conversation?.id ?? -1,
      senderId: AuthService.currentUser?.id ?? 0,
      senderName: AuthService.currentUser?.fullName ?? 'You',
      clientMessageId: clientMessageId,
      content: text,
      messageType: messageType,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now(),
      deliveryStatus: 'pending',
    );

    setState(() {
      _isSending = true;
      _messages.add(pendingMessage);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      if (_conversation == null) {
        final queuedConversation =
            await ChatService.startConversationAndSendMessageQueued(
              rentalId: widget.rental.id != null && widget.rental.id! > 0
                  ? widget.rental.id
                  : null,
              targetUserId: widget.rental.id == null || widget.rental.id! <= 0
                  ? _otherUserId
                  : null,
              content: text,
              messageType: messageType,
              mediaUrl: mediaUrl,
              clientMessageId: clientMessageId,
            );
        final conversation = queuedConversation.conversation;
        setState(() {
          _conversation = conversation;
        });
        _applySafetyStatus(
          ChatSafetyStatus(
            mutedByMe: conversation.mutedByMe,
            blockedByMe: conversation.blockedByMe,
            blockedMe: conversation.blockedMe,
          ),
        );
        _startPolling();
        _subscribeConversationChannel();
        unawaited(_refreshChatSafetyStatus());
        final queuedResult = queuedConversation.messageResult;
        if (queuedResult.isSent && queuedResult.message != null) {
          _onRealtimeMessage(queuedResult.message!);
        } else if (queuedResult.isFailed) {
          _markMessageFailed(clientMessageId);
          unawaited(_refreshChatSafetyStatus());
        } else {
          _schedulePendingMessageReconciliation();
        }
      } else {
        final conversationId = _conversation?.id;
        if (conversationId == null) {
          throw Exception('Conversation was not initialized.');
        }

        final queuedResult = await ChatService.sendMessageQueued(
          conversationId: conversationId,
          content: text,
          messageType: messageType,
          mediaUrl: mediaUrl,
          clientMessageId: clientMessageId,
        );

        if (queuedResult.isSent && queuedResult.message != null) {
          _onRealtimeMessage(queuedResult.message!);
        } else if (queuedResult.isFailed) {
          _markMessageFailed(clientMessageId);
          unawaited(_refreshChatSafetyStatus());
        } else {
          _schedulePendingMessageReconciliation();
        }
      }
    } catch (e) {
      _markMessageFailed(clientMessageId);
      unawaited(_refreshChatSafetyStatus());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallbackMessage: 'Failed to send message.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _markMessageFailed(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere(
        (m) => m.clientMessageId == clientMessageId,
      );
      if (index < 0) return;
      final existing = _messages[index];
      _messages[index] = ChatMessage(
        id: existing.id,
        conversationId: existing.conversationId,
        senderId: existing.senderId,
        senderName: existing.senderName,
        clientMessageId: existing.clientMessageId,
        content: existing.content,
        messageType: existing.messageType,
        mediaUrl: existing.mediaUrl,
        localPath: existing.localPath,
        createdAt: existing.createdAt,
        isRead: existing.isRead,
        deliveryStatus: 'failed',
      );
    });
  }

  Future<void> _retryFailedMessage(ChatMessage message) async {
    if (message.clientMessageId == null) return;

    setState(() {
      final index = _messages.indexWhere(
        (m) => m.clientMessageId == message.clientMessageId,
      );
      if (index >= 0) {
        final existing = _messages[index];
        _messages[index] = ChatMessage(
          id: existing.id,
          conversationId: existing.conversationId,
          senderId: existing.senderId,
          senderName: existing.senderName,
          clientMessageId: existing.clientMessageId,
          content: existing.content,
          messageType: existing.messageType,
          mediaUrl: existing.mediaUrl,
          localPath: existing.localPath,
          createdAt: existing.createdAt,
          isRead: existing.isRead,
          deliveryStatus: 'pending',
        );
      }
    });

    int? conversationId = _conversation?.id;
    if (conversationId == null) {
      try {
        final queuedConversation =
            await ChatService.startConversationAndSendMessageQueued(
              rentalId: widget.rental.id != null && widget.rental.id! > 0
                  ? widget.rental.id
                  : null,
              targetUserId: widget.rental.id == null || widget.rental.id! <= 0
                  ? _otherUserId
                  : null,
              content: message.content,
              clientMessageId: message.clientMessageId!,
            );
        final conversation = queuedConversation.conversation;
        if (!mounted) return;
        setState(() => _conversation = conversation);
        _applySafetyStatus(
          ChatSafetyStatus(
            mutedByMe: conversation.mutedByMe,
            blockedByMe: conversation.blockedByMe,
            blockedMe: conversation.blockedMe,
          ),
        );
        _startPolling();
        _subscribeConversationChannel();
        unawaited(_refreshChatSafetyStatus());
        final queuedResult = queuedConversation.messageResult;
        if (queuedResult.isSent && queuedResult.message != null) {
          _onRealtimeMessage(queuedResult.message!);
        } else if (queuedResult.isFailed) {
          _markMessageFailed(message.clientMessageId!);
        } else {
          _schedulePendingMessageReconciliation();
        }
        return;
      } catch (_) {
        _markMessageFailed(message.clientMessageId!);
        return;
      }
    }
    final resolvedConversationId = conversationId;

    try {
      final queuedResult = await ChatService.sendMessageQueued(
        conversationId: resolvedConversationId,
        content: message.content,
        clientMessageId: message.clientMessageId!,
      );
      if (queuedResult.isSent && queuedResult.message != null) {
        _onRealtimeMessage(queuedResult.message!);
      } else if (queuedResult.isFailed) {
        _markMessageFailed(message.clientMessageId!);
      } else {
        _schedulePendingMessageReconciliation();
      }
    } catch (_) {
      _markMessageFailed(message.clientMessageId!);
    }
  }

  void _schedulePendingMessageReconciliation() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      unawaited(_pollForNewMessages());
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.image, color: Colors.white),
                  ),
                  title: const Text('Gallery'),
                  subtitle: const Text('Share photos or videos'),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => WhatsappGallerySheet(),
                    );
                    if (result != null) {
                      if (result['action'] == 'see_more') {
                        final picker = ImagePicker();
                        final xfile = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (xfile != null) {
                          await _processAndSendImage(xfile);
                        }
                      } else if (result['type'] == 'native_app') {
                        final packageName = result['packageName'] as String;
                        final className = result['className'] as String;
                        final xfiles = await NativeAppPicker.pickFromApp(packageName, className);
                        for (final xfile in xfiles) {
                          await _processAndSendImage(xfile);
                        }
                      } else {
                        final file = result['file'] as File;
                        final caption = result['caption'] as String;
                        await _sendPreparedImage(file, caption);
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.camera_alt, color: Colors.white),
                  ),
                  title: const Text('Camera'),
                  subtitle: const Text('Take a photo'),
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (xfile != null) {
                      await _processAndSendImage(xfile);
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: const Text('Contact'),
                  subtitle: const Text('Share a contact'),
                  onTap: () async {
                    Navigator.pop(context);
                    final status = await FlutterContacts.permissions.request(
                      PermissionType.read,
                    );
                    if (status == PermissionStatus.granted) {
                      final contact = await FlutterContacts.native.showPicker();
                      if (contact != null && contact.id != null) {
                        final fullContact = await FlutterContacts.get(
                          contact.id!,
                          properties: {ContactProperty.phone},
                        );
                        if (fullContact != null && mounted) {
                          final phone = fullContact.phones.isNotEmpty
                              ? fullContact.phones.first.number
                              : '';
                          final name = fullContact.displayName;
                          await _sendMessage(
                            content: '{"name": "$name", "phone": "$phone"}',
                            messageType: 'CONTACT',
                          );
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact permission denied'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _processAndSendImage(XFile xfile) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FilePreviewSheet(
          file: File(xfile.path),
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null && mounted) {
      final file = result['file'] as File;
      final caption = result['caption'] as String;
      await _sendPreparedImage(file, caption);
    }
  }

  Future<void> _sendPreparedImage(File imageFile, String caption) async {
    setState(() => _isSending = true);
    try {
      final url = await ApiService.uploadFile(
        imageFile,
        '/files/upload',
        token: AuthService.token,
      );
      await _sendMessage(
        content: caption.isNotEmpty ? caption : 'Sent an image',
        messageType: 'IMAGE',
        mediaUrl: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () {
            if (widget.rental.propertyType == 'HELPER') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HelperProfilePage(
                    helperId: _otherUserId,
                    helperName: _otherUserName,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      UserPublicProfilePage(userId: _otherUserId),
                ),
              );
            }
          },
          child: Row(
            children: [
              FullScreenImageAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                avatarUrl: _otherUserAvatarUrl,
                fallbackWidget: Text(
                  _otherUserName.isNotEmpty
                      ? _otherUserName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.rental.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    _isOtherUserTyping
                        ? Text(
                            'typing...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : Text(
                            ContactService.getDisplayName(
                              _otherUserId,
                              _otherUserName,
                              username: _otherUserUsername,
                            ),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.rental.propertyType == 'HELPER')
            TextButton.icon(
              icon: const Icon(
                Icons.rate_review,
                color: Colors.white,
                size: 18,
              ),
              label: const Text(
                'Review',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HelperProfilePage(
                      helperId: _otherUserId,
                      helperName: _otherUserName,
                    ),
                  ),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showSaveContactDialog(
              context,
              _otherUserId,
              _otherUserName,
              _otherUserUsername,
            ),
            tooltip: 'Save Contact',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'mute':
                  _toggleMute();
                  break;
                case 'block':
                  _toggleBlock();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  _chatSafety.mutedByMe
                      ? 'Unmute notifications'
                      : 'Mute notifications',
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  _chatSafety.blockedByMe ? 'Unblock contact' : 'Block contact',
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chatSafety.blockedByMe || _chatSafety.blockedMe)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Colors.orange.withOpacity(0.12),
              child: Text(
                _chatSafety.blockedByMe
                    ? 'You blocked this contact. Unblock to send messages.'
                    : 'This contact blocked you. Messaging is disabled.',
                style: TextStyle(color: Colors.orange[900]),
              ),
            ),
          // Rental info card
          if (widget.rental.id != 0)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[100],
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.rental.imageUrls.isNotEmpty
                        ? Image.network(
                            widget.rental.imageUrls.first,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 60,
                                height: 60,
                                color: Colors.grey[300],
                                child: const Icon(Icons.home),
                              );
                            },
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[300],
                            child: const Icon(Icons.home),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.rental.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.rental.formattedPrice,
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: DwellyOrbitingLoader(size: 64))
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _messages.isEmpty && _conversation == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start a conversation',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Send a message to the owner about this property',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        _messages.length +
                        (_isLoadingMore || _hasMoreMessages ? 1 : 0) +
                        (_isOtherUserTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoadingMore || _hasMoreMessages) {
                        if (index == 0) {
                          if (_isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: DwellyOrbitingLoader(),
                                ),
                              ),
                            );
                          } else {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: TextButton.icon(
                                  onPressed: _loadMoreMessages,
                                  icon: const Icon(Icons.history, size: 16),
                                  label: const Text('Load earlier messages'),
                                ),
                              ),
                            );
                          }
                        }
                        index -= 1;
                      }

                      if (_isOtherUserTyping && index == _messages.length) {
                        return const _TypingIndicatorBubble();
                      }

                      final message = _messages[index];
                      final isMe = message.senderId == currentUserId;
                      return _MessageBubble(
                        message: message,
                        isMe: isMe,
                        onDownloadVideo: message.isVideo
                            ? () => _downloadVideo(message, index)
                            : null,
                        onPlayVideo:
                            (message.isVideo && message.localPath != null)
                            ? () => _playLocalVideo(message)
                            : null,
                        onRetry: message.isFailed
                            ? () => _retryFailedMessage(message)
                            : null,
                        onDelete: (deleteForAll) =>
                            _deleteMessage(message, deleteForAll: deleteForAll),
                        isLastMessage: index == _messages.length - 1,
                      );
                    },
                  ),
          ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          enabled:
                              !(_chatSafety.blockedByMe ||
                                  _chatSafety.blockedMe),
                          decoration: InputDecoration(
                            prefixIcon: IconButton(
                              icon: Icon(
                                _isEmojiPickerVisible
                                    ? Icons.keyboard
                                    : Icons.emoji_emotions_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: () {
                                setState(() {
                                  _isEmojiPickerVisible =
                                      !_isEmojiPickerVisible;
                                  if (_isEmojiPickerVisible) {
                                    _focusNode.unfocus();
                                  } else {
                                    _focusNode.requestFocus();
                                  }
                                });
                              },
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: Colors.grey[600],
                              ),
                              onPressed: _showAttachmentOptions,
                            ),
                            hintText:
                                _chatSafety.blockedByMe || _chatSafety.blockedMe
                                ? 'Messaging disabled'
                                : 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(0.55)
                                : Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onChanged: _onMessageChanged,
                          onSubmitted: (_) {
                            if (!(_chatSafety.blockedByMe ||
                                _chatSafety.blockedMe)) {
                              _sendMessage();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        child: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: DwellyOrbitingLoader(
                                  glowColor: Colors.white,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                ),
                                onPressed:
                                    _chatSafety.blockedByMe ||
                                        _chatSafety.blockedMe
                                    ? null
                                    : _sendMessage,
                              ),
                      ),
                    ],
                  ),
                  if (_isEmojiPickerVisible)
                    SizedBox(
                      height: 250,
                      child: EmojiPicker(
                        textEditingController: _messageController,
                        config: Config(
                          height: 250,
                          checkPlatformCompatibility: true,
                          emojiViewConfig: EmojiViewConfig(
                            emojiSizeMax:
                                32 *
                                (foundation.defaultTargetPlatform ==
                                        TargetPlatform.iOS
                                    ? 1.30
                                    : 1.0),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                          ),
                          bottomActionBarConfig: BottomActionBarConfig(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            buttonIconColor: Colors.grey,
                            buttonColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMessageChanged(String text) {
    if (!_isRealtimeConnected || _conversation == null) return;
    _realtimeService.sendTypingEvent(_conversation!.id!, text.isNotEmpty);
    _typingTimer?.cancel();
    if (text.isNotEmpty) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _realtimeService.sendTypingEvent(_conversation!.id!, false);
      });
    }
  }

  Future<void> _deleteMessage(
    ChatMessage message, {
    bool deleteForAll = false,
  }) async {
    if (message.id == null) return;
    try {
      await ChatService.deleteMessage(message.id!, deleteForAll: deleteForAll);
      if (mounted) {
        setState(() {
          if (deleteForAll) {
            message.content = 'This message was deleted';
            message.messageType = 'DELETED';
            message.mediaUrl = null;
          } else {
            _messages.removeWhere((m) => m.id == message.id);
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
      }
    }
  }

  // ── Video download & local storage ──────────────────────────────────

  Future<void> _downloadVideo(ChatMessage message, int index) async {
    if (message.mediaUrl == null && message.localPath == null) return;

    // If already downloaded, just play
    if (message.localPath != null && File(message.localPath!).existsSync()) {
      _playLocalVideo(message);
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Downloading video...')));

    try {
      String videoUrl = message.mediaUrl!;
      if (videoUrl.startsWith('/')) {
        final baseWithoutApi = ApiService.baseUrl.replaceAll('/api', '');
        videoUrl = '$baseWithoutApi${message.mediaUrl}';
      }

      final response = await http.get(
        Uri.parse(videoUrl),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${dir.path}/chat_videos');
      if (!videosDir.existsSync()) {
        videosDir.createSync(recursive: true);
      }
      final ext = videoUrl.contains('.')
          ? videoUrl.substring(videoUrl.lastIndexOf('.'))
          : '.mp4';
      final localFile = File('${videosDir.path}/${message.id}$ext');
      await localFile.writeAsBytes(response.bodyBytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('video_local_${message.id}', localFile.path);

      setState(() {
        _messages[index].localPath = localFile.path;
      });

      // Keep media available for other devices/participants and extend retention.
      if (message.id != null) {
        unawaited(ChatService.markMessageMediaAccessed(message.id!));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _playLocalVideo(ChatMessage message) {
    if (message.localPath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoPlayerScreen(filePath: message.localPath!),
      ),
    );
  }
}

// ── Message Bubble ──────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onDownloadVideo;
  final VoidCallback? onPlayVideo;
  final VoidCallback? onRetry;
  final void Function(bool deleteForAll)? onDelete;
  final bool isLastMessage;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onDownloadVideo,
    this.onPlayVideo,
    this.onRetry,
    this.onDelete,
    this.isLastMessage = false,
  });

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Text copied')));
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.orange),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(color: Colors.orange),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!(false);
                },
              ),
            if (isMe && onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!(true);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (message.messageType.toUpperCase() == 'SAFETY_WARNING') {
      return _buildSafetyWarning(context);
    }

    final bool hasMedia = message.messageType == 'IMAGE' || message.isVideo;
    final bool isMediaOnly = hasMedia &&
        (message.content.isEmpty ||
            message.content == 'Sent an image' ||
            message.content == 'Sent a video');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              _showOptions(context);
            },
            child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: hasMedia
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMediaOnly
                ? Colors.transparent
                : (isMe ? Theme.of(context).primaryColor : Colors.grey[200]),
            borderRadius: BorderRadius.circular(20).copyWith(
              bottomRight: isMe ? const Radius.circular(4) : null,
              bottomLeft: !isMe ? const Radius.circular(4) : null,
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && !isMediaOnly)
                Padding(
                  padding: hasMedia ? const EdgeInsets.fromLTRB(12, 8, 12, 4) : const EdgeInsets.only(bottom: 4),
                  child: Text(
                    ContactService.getDisplayName(
                      message.senderId,
                      message.senderName,
                      username: message.senderUsername,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ),

              // Video message
              if (message.isVideo) _buildVideoContent(context),

              // Image message
              if (message.messageType == 'IMAGE' && message.mediaUrl != null)
                GestureDetector(
                  onTap: () {
                    final imageUrl = message.mediaUrl!.startsWith('http')
                        ? message.mediaUrl!
                        : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FullScreenImageView(imageUrl: imageUrl),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: isMediaOnly
                        ? BorderRadius.circular(20).copyWith(
                            bottomRight: isMe ? const Radius.circular(4) : null,
                            bottomLeft: !isMe ? const Radius.circular(4) : null,
                          )
                        : const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Stack(
                      children: [
                        Hero(
                          tag: message.mediaUrl!.startsWith('http')
                              ? message.mediaUrl!
                              : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}',
                          child: CachedNetworkImage(
                            imageUrl: message.mediaUrl!.startsWith('http')
                                ? message.mediaUrl!
                                : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}',
                            width: isMediaOnly ? 250 : double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth: 600,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => Container(
                              width: isMediaOnly ? 250 : double.infinity,
                              height: 200,
                              color: Colors.grey[850],
                            ),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(message.createdAt),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  _buildDeliveryIcon(context),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Location Message
              if (message.messageType == 'LIVE_LOCATION')
                _buildLocationBubble(context),

              // Contact Message
              if (message.messageType == 'CONTACT')
                _buildContactBubble(context),

              // Listing Share Message
              if (message.isListingShare) _buildListingShareCard(context),

              // Caption / Text message
              if (message.messageType == 'TEXT' || (!isMediaOnly && hasMedia))
                Padding(
                  padding: hasMedia ? const EdgeInsets.fromLTRB(12, 8, 12, 10) : EdgeInsets.zero,
                  child: Linkify(
                    onOpen: (link) async {
                      final url = Uri.parse(link.url);
                      try {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open link: ${link.url}')),
                          );
                        }
                      }
                    },
                    text: message.content,
                    style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                    linkStyle: TextStyle(
                      color: isMe ? Colors.white : Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                    ),
                    options: const LinkifyOptions(humanize: false),
                    linkifiers: const [
                      EmailLinkifier(),
                      UrlLinkifier(),
                      PhoneNumberLinkifier(),
                    ],
                  ),
                ),

              const SizedBox(height: 4),
              if (!hasMedia)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : Colors.grey[500],
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      _buildDeliveryIcon(context),
                    ],
                  ],
                ),
            ],
          ),
          ),
        ),
        if (isMe && isLastMessage && message.isRead)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 4),
            child: Text(
              'Seen',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyWarning(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.shield_outlined, size: 18, color: Colors.amber),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.content,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.amber[100]
                      : Colors.brown[800],
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryIcon(BuildContext context) {
    if (message.isLocalPending) {
      return Icon(
        Icons.schedule,
        size: 13,
        color: isMe ? Colors.white70 : Colors.grey[500],
      );
    }
    if (message.isFailed) {
      return GestureDetector(
        onTap: onRetry,
        child: Icon(
          Icons.error_outline,
          size: 14,
          color: isMe ? Colors.red[100] : Colors.red[600],
        ),
      );
    }
    return Icon(
      Icons.done_all,
      size: 14,
      color: isMe ? Colors.white70 : Colors.grey[500],
    );
  }

  Widget _buildVideoContent(BuildContext context) {
    final hasLocal =
        message.localPath != null && File(message.localPath!).existsSync();
    final hasRemote = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;

    if (hasLocal) {
      return GestureDetector(
        onTap: onPlayVideo,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_fill,
                  size: 48,
                  color: isMe ? Colors.white : Colors.blue,
                ),
                const SizedBox(height: 4),
                Text(
                  'Play Video',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (hasRemote) {
      return GestureDetector(
        onTap: onDownloadVideo,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_rounded,
                  size: 48,
                  color: isMe ? Colors.white : Colors.blue,
                ),
                const SizedBox(height: 4),
                Text(
                  'Download Video',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off,
            size: 18,
            color: isMe ? Colors.white70 : Colors.grey[500],
          ),
          const SizedBox(width: 6),
          Text(
            'Video no longer available',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: isMe ? Colors.white70 : Colors.grey[500],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLocationBubble(BuildContext context) {
    try {
      final data = jsonDecode(message.content);
      final lat = data['lat'];
      final lng = data['lng'];
      return GestureDetector(
        onTap: () async {
          final url = Uri.parse('https://maps.google.com/?q=$lat,$lng');
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
          }
        },
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withValues(alpha: 0.2) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.map, size: 40, color: Colors.blue),
              const SizedBox(height: 8),
              Text(
                'Live Location',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                'Tap to open map',
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return Text('Invalid location data', style: TextStyle(color: Colors.red));
    }
  }

  Future<void> _startChatWithMatch(
    BuildContext context,
    ContactMatch match,
  ) async {
    var isLoadingShown = false;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: DwellyOrbitingLoader()),
      );
      isLoadingShown = true;
      final conversation = await ChatService.startConversation(
        targetUserId: match.userId,
      );
      if (!context.mounted) return;
      if (isLoadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        isLoadingShown = false;
      }

      final pseudoRental = Rental(
        id: conversation.rentalId,
        ownerId: conversation.ownerId,
        title: conversation.listingTitle ?? 'Chat',
        description: conversation.lastMessage ?? '',
        price: 0,
        address: conversation.listingTitle ?? 'Direct Message',
        city: '',
        state: '',
        bedrooms: 0,
        bathrooms: 0,
        squareFeet: 0,
        propertyType: 'OTHER',
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            rental: pseudoRental,
            existingConversation: conversation,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        if (isLoadingShown) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting chat: $e')),
        );
      }
    }
  }

  Widget _buildContactBubble(BuildContext context) {
    try {
      final data = jsonDecode(message.content);
      final name = data['name'] ?? 'Unknown';
      final phone = data['phone'] ?? '';
      return GestureDetector(
        onTap: () async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(child: DwellyOrbitingLoader()),
          );

          final normalized = phone.replaceAll(RegExp(r'\D'), '');
          ContactMatch? match;
          if (normalized.isNotEmpty) {
            try {
              final response = await ApiService.timedPost(
                Uri.parse('${ApiService.baseUrl}/contacts/sync'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${AuthService.token}',
                },
                body: jsonEncode({'identifiers': [normalized]}),
              );
              if (response.statusCode == 200) {
                final List<dynamic> resData = jsonDecode(response.body);
                if (resData.isNotEmpty) {
                  match = ContactMatch.fromJson(resData.first);
                }
              }
            } catch (_) {}
          }

          if (!context.mounted) return;
          Navigator.pop(context); // pop loading dialog

          showModalBottomSheet(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match != null)
                    ListTile(
                      leading: Stack(
                        children: [
                          Image.asset('assets/images/icon.png', width: 24, height: 24),
                          const Positioned(
                            right: -2,
                            bottom: -2,
                            child: Icon(Icons.check_circle, color: Colors.blue, size: 12),
                          ),
                        ],
                      ),
                      title: const Text('Message on IshinaDwelly'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        _startChatWithMatch(context, match!);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.message),
                    title: Text('Message $name via SMS'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final url = Uri.parse('sms:$phone');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      }
                    },
                  ),
                  if (phone.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.call),
                      title: Text('Call $name'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final url = Uri.parse('tel:$phone');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.person_add),
                    title: const Text('Save Contact'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        final status = await FlutterContacts.permissions.request(
                          PermissionType.write,
                        );
                        if (status != PermissionStatus.granted) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Permission denied to save contact')),
                            );
                          }
                          return;
                        }

                        final newContact = Contact(
                          name: Name(first: name),
                          phones: [Phone(number: phone)],
                        );
                        await FlutterContacts.create(newContact);
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Contact saved to device')),
                          );
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text('Could not save contact: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withValues(alpha: 0.2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 14,
                              color: isMe ? Colors.white70 : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Message',
                  style: TextStyle(
                    color: isMe ? Colors.white : Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return Text('Invalid contact data', style: TextStyle(color: Colors.red));
    }
  }

  Widget _buildListingShareCard(BuildContext context) {
    try {
      final data = jsonDecode(message.content);
      final id = data['id'];
      final title = data['title'] ?? 'Listing';
      final price = data['price'] ?? '';
      final location = data['location'] ?? '';
      final imageUrl = data['imageUrl'];

      return GestureDetector(
        onTap: () {
          if (id != null) {
            DeepLinkService.navigateToListingById(id.toString());
          }
        },
        child: Container(
          width: 240,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withValues(alpha: 0.15) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(width: 0, color: Colors.transparent),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null && imageUrl.toString().isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl.toString().startsWith('http')
                      ? imageUrl.toString()
                      : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}$imageUrl',
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, __) => Container(
                    height: 130,
                    color: isMe ? Colors.white24 : Colors.grey[200],
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 130,
                    color: isMe ? Colors.white24 : Colors.grey[200],
                    child: Icon(
                      Icons.home,
                      color: isMe ? Colors.white : Colors.grey,
                      size: 40,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isMe ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isMe
                            ? Colors.amberAccent
                            : Theme.of(context).primaryColor,
                      ),
                    ),
                    if (location.toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          location.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isMe ? Colors.white70 : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.25)
                            : Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'View Listing →',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isMe ? Colors.white : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return Text(
        'Shared Listing: ${message.content}',
        style: TextStyle(color: isMe ? Colors.white : Colors.black87),
      );
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// ── Full-screen Video Player ────────────────────────────────────────

class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;

  const _VideoPlayerScreen({required this.filePath});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Video', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                      child: AnimatedOpacity(
                        opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          color: Colors.black26,
                          child: const Icon(
                            Icons.play_arrow,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.blue,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const DwellyOrbitingLoader(glowColor: Colors.white),
      ),
    );
  }
}

class ImageCaptionScreen extends StatefulWidget {
  final File imageFile;

  const ImageCaptionScreen({super.key, required this.imageFile});

  @override
  State<ImageCaptionScreen> createState() => _ImageCaptionScreenState();
}

class _ImageCaptionScreenState extends State<ImageCaptionScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Container(
              color: Colors.black.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                          filled: true,
                          fillColor: Colors.grey[900],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context, _controller.text);
                      },
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        radius: 24,
                        child: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble();

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

    _animation1 = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)));
    _animation2 = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeInOut)));
    _animation3 = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -5 * math.sin(animation.value * math.pi)),
          child: Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(_animation1),
            _buildDot(_animation2),
            _buildDot(_animation3),
          ],
        ),
      ),
    );
  }
}

