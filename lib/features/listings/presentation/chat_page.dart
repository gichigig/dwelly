import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/chat.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/chat_realtime_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/offline_queue_service.dart';
import '../../../core/widgets/tutorial_overlay.dart';
import '../../../core/widgets/full_screen_image_avatar.dart';
import '../../../core/services/contact_service.dart';
import '../../user_profile/presentation/user_public_profile_page.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';
import 'dart:convert';
import '../../../core/services/helper_job_service.dart';
import '../../helper/presentation/helper_profile_page.dart';

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
  StreamSubscription<String>? _offlineQueueSubscription;
  ChatSafetyStatus _chatSafety = const ChatSafetyStatus.none();
  
  bool _isEmojiPickerVisible = false;
  final FocusNode _focusNode = FocusNode();
  bool _hasActiveHelperJob = false;

  // Pagination state
  int _currentPage = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  static const int _messagesPerPage = 10;

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

  void _showSaveContactDialog(BuildContext context, int userId, String currentName, String? username) {
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

  void _showHireModal(BuildContext context) {
    final phoneController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hire ${_otherUserName}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Price: KES ${widget.rental.price.toStringAsFixed(2)}'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'M-Pesa Phone Number',
                        hintText: 'e.g. 254712345678',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (phoneController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter your M-Pesa number')),
                                  );
                                  return;
                                }
                                
                                setModalState(() => isSubmitting = true);
                                try {
                                  await HelperJobService.hireHelper(
                                    helperId: _otherUserId,
                                    phoneNumber: phoneController.text,
                                  );
                                  
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Hiring request sent! Please check your phone for the M-Pesa prompt.')),
                                    );
                                  }
                                  if (mounted) {
                                    setState(() => _hasActiveHelperJob = true);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Send Request & Pay via M-Pesa', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
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
    NotificationService.clearMessageNotifications();
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
    // For helper chats, check if payment already made to hide the Hire & Pay button
    if (widget.rental.propertyType == 'HELPER' && AuthService.isLoggedIn) {
      _checkHelperJobStatus();
    }
    
    _offlineQueueSubscription = OfflineQueueService.onMessageSent.listen((clientMessageId) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.clientMessageId == clientMessageId);
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
    if (_scrollController.position.pixels <= 100 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        !_isLoading) {
      _loadMoreMessages();
    }
  }

  void _startPolling() {
    // Poll fallback when live socket is unavailable.
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollForNewMessages();
    });
  }

  Future<void> _checkHelperJobStatus() async {
    final helperId = _otherUserId;
    if (helperId == 0) return;
    final hasJob = await HelperJobService.hasActiveJobWithHelper(helperId);
    if (mounted) {
      setState(() => _hasActiveHelperJob = hasJob);
    }
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
        _subscribeConversationChannel();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isRealtimeConnected = false);
      },
    );
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
      
      ChatService.markConversationAsReadLocal(_conversation!.id!);
      
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
        _messages = [...olderMessages, ..._messages];
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
              rentalId: widget.rental.id != null && widget.rental.id! > 0 ? widget.rental.id : null,
              targetUserId: widget.rental.id == null || widget.rental.id! <= 0 ? _otherUserId : null,
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
              rentalId: widget.rental.id != null && widget.rental.id! > 0 ? widget.rental.id : null,
              targetUserId: widget.rental.id == null || widget.rental.id! <= 0 ? _otherUserId : null,
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
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(source: ImageSource.gallery);
                  if (xfile != null && mounted) {
                    setState(() => _isSending = true);
                    try {
                      final url = await ApiService.uploadFile(
                        File(xfile.path),
                        '/files/upload',
                        token: AuthService.token,
                      );
                      await _sendMessage(
                        content: 'Sent an image',
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
                  final xfile = await picker.pickImage(source: ImageSource.camera);
                  if (xfile != null && mounted) {
                    setState(() => _isSending = true);
                    try {
                      final url = await ApiService.uploadFile(
                        File(xfile.path),
                        '/files/upload',
                        token: AuthService.token,
                      );
                      await _sendMessage(
                        content: 'Sent an image',
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
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.location_on, color: Colors.white),
                ),
                title: const Text('Current Location'),
                subtitle: const Text('Share your current location'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                    if (!serviceEnabled) throw Exception('Location disabled');
                    LocationPermission permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                      if (permission == LocationPermission.denied) throw Exception('Permission denied');
                    }
                    final pos = await Geolocator.getCurrentPosition();
                    _messageController.text = '📍 Shared Location: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
                    _sendMessage();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not get location: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.share_location, color: Colors.white),
                ),
                title: const Text('Live Location'),
                subtitle: const Text('Share your real-time location'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                    if (!serviceEnabled) throw Exception('Location disabled');
                    LocationPermission permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                      if (permission == LocationPermission.denied) throw Exception('Permission denied');
                    }
                    final pos = await Geolocator.getCurrentPosition();
                    await _sendMessage(
                      content: '{"lat": ${pos.latitude}, "lng": ${pos.longitude}}',
                      messageType: 'LIVE_LOCATION',
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not share live location: $e')),
                      );
                    }
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
                  final status = await FlutterContacts.permissions.request(PermissionType.read);
                  if (status == PermissionStatus.granted) {
                    final contact = await FlutterContacts.native.showPicker();
                    if (contact != null && contact.id != null) {
                      final fullContact = await FlutterContacts.get(contact.id!, properties: {ContactProperty.phone});
                      if (fullContact != null && mounted) {
                        final phone = fullContact.phones.isNotEmpty ? fullContact.phones.first.number : '';
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
                        const SnackBar(content: Text('Contact permission denied')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
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
                  builder: (context) => HelperProfilePage(helperId: _otherUserId, helperName: _otherUserName),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPublicProfilePage(userId: _otherUserId),
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
                  _otherUserName.isNotEmpty ? _otherUserName[0].toUpperCase() : '?',
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
                    Text(widget.rental.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    Text(
                      ContactService.getDisplayName(_otherUserId, _otherUserName, username: _otherUserUsername),
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
          if (widget.rental.propertyType == 'HELPER' && !_hasActiveHelperJob)
            TextButton.icon(
              icon: const Icon(Icons.payment, color: Colors.white),
              label: const Text('Hire & Pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () => _showHireModal(context),
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showSaveContactDialog(context, _otherUserId, _otherUserName, _otherUserUsername),
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
                ? const Center(child: CircularProgressIndicator())
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
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
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
                        onDelete: () => _deleteMessage(message),
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
                      IconButton(
                        icon: Icon(
                          _isEmojiPickerVisible 
                              ? Icons.keyboard 
                              : Icons.emoji_emotions_outlined,
                          color: Colors.grey[600],
                        ),
                        onPressed: () {
                          setState(() {
                            _isEmojiPickerVisible = !_isEmojiPickerVisible;
                            if (_isEmojiPickerVisible) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.add_circle_outline, color: Colors.grey[600]),
                        onPressed: _showAttachmentOptions,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                      enabled:
                          !(_chatSafety.blockedByMe || _chatSafety.blockedMe),
                      decoration: InputDecoration(
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
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed:
                                _chatSafety.blockedByMe || _chatSafety.blockedMe
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
                        emojiSizeMax: 32 * (foundation.defaultTargetPlatform == TargetPlatform.iOS ? 1.30 : 1.0),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        backgroundColor: Theme.of(context).colorScheme.surface,
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

  Future<void> _deleteMessage(ChatMessage message) async {
    if (message.id == null) return;
    try {
      await ChatService.deleteMessage(message.id!);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
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
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onDownloadVideo,
    this.onPlayVideo,
    this.onRetry,
    this.onDelete,
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Text copied')),
                );
              },
            ),
            if (isMe && onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          if (message.messageType == 'TEXT') {
            _showOptions(context);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? Theme.of(context).primaryColor : Colors.grey[200],
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
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  ContactService.getDisplayName(message.senderId, message.senderName, username: message.senderUsername),
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
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: message.mediaUrl!.startsWith('http')
                        ? message.mediaUrl!
                        : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}',
                    width: 200,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                ),
              ),

            // Location Message
            if (message.messageType == 'LIVE_LOCATION')
              _buildLocationBubble(context),

            // Contact Message
            if (message.messageType == 'CONTACT')
              _buildContactBubble(context),

            // Text message
            if (message.messageType == 'TEXT')
              Linkify(
                onOpen: (link) async {
                  final url = Uri.parse(link.url);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open link')),
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
                linkifiers: const [EmailLinkifier(), UrlLinkifier(), PhoneNumberLinkifier()],
              ),

            const SizedBox(height: 4),
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

  Widget _buildContactBubble(BuildContext context) {
    try {
      final data = jsonDecode(message.content);
      final name = data['name'] ?? 'Unknown';
      final phone = data['phone'] ?? '';
      return Container(
        width: 200,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              child: Icon(Icons.person),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (phone.isNotEmpty)
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white70 : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return Text('Invalid contact data', style: TextStyle(color: Colors.red));
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
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
