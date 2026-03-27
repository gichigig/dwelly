import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  ChatSafetyStatus _chatSafety = const ChatSafetyStatus.none();

  // Pagination state
  int _currentPage = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  static const int _messagesPerPage = 10;

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
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _conversationUnsubscribe?.call();
    _statusUnsubscribe?.call();
    _realtimeService.disconnect();
    _messageController.dispose();
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
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
              rentalId: widget.rental.id!,
              content: text,
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
              rentalId: widget.rental.id!,
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

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.rental.title, style: const TextStyle(fontSize: 16)),
            Text(
              widget.rental.ownerName ?? 'Owner',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
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
            ),
          ),
        ],
      ),
    );
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

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onDownloadVideo,
    this.onPlayVideo,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (message.messageType.toUpperCase() == 'SAFETY_WARNING') {
      return _buildSafetyWarning(context);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                  message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ),

            // Video message
            if (message.isVideo) _buildVideoContent(context),

            // Text message
            if (!message.isVideo)
              Text(
                message.content,
                style: TextStyle(color: isMe ? Colors.white : Colors.black87),
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
