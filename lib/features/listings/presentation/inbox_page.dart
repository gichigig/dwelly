import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/rental.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/widgets/telegram/telegram_section_state.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import 'chat_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  static const int _pageSize = 10;

  final ScrollController _scrollController = ScrollController();
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  int _totalConversations = 0;
  String? _error;
  Timer? _pollingTimer;

  void _syncUnreadBadgeFromConversations() {
    ChatService.unreadMessageCount.value = _conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    NotificationService.clearMessageNotifications();
    _loadConversations();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadConversations(forceRefresh: true);
    }
  }

  void _startPolling() {
    // Poll for conversation updates every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollForUpdates();
    });
  }

  Future<void> _pollForUpdates() async {
    if (!AuthService.isLoggedIn || _isLoading || _isLoadingMore) return;

    try {
      final result = await ChatService.getConversationsPaginated(
        page: 0,
        size: _pageSize,
        forceRefresh: true,
      );
      final latestFirstPage = result.conversations;

      if (mounted) {
        setState(() {
          if (_conversations.length <= _pageSize) {
            _conversations = latestFirstPage;
          } else {
            final trailing = _conversations.skip(_pageSize);
            _conversations = [...latestFirstPage, ...trailing];
          }
          _totalConversations = result.totalConversations;
          _hasMore =
              result.hasMore || _conversations.length < _totalConversations;
        });
        _syncUnreadBadgeFromConversations();
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreConversations();
    }
  }

  void _loadMoreConversations() {
    if (_isLoadingMore || !_hasMore) return;

    _loadConversations(loadMore: true);
  }

  Future<void> _loadConversations({
    bool forceRefresh = false,
    bool loadMore = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      ChatService.unreadMessageCount.value = 0;
      setState(() {
        _isLoading = false;
        _conversations = [];
        _isLoadingMore = false;
        _hasMore = false;
        _currentPage = 0;
        _totalConversations = 0;
      });
      return;
    }

    if (loadMore && (_isLoadingMore || !_hasMore)) return;

    setState(() {
      _error = null;
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final nextPage = loadMore ? _currentPage + 1 : 0;
      final result = await ChatService.getConversationsPaginated(
        page: nextPage,
        size: _pageSize,
        forceRefresh: forceRefresh,
      );
      final conversations = result.conversations;

      setState(() {
        if (loadMore) {
          _conversations = [..._conversations, ...conversations];
        } else {
          _conversations = conversations;
        }
        _currentPage = result.page;
        _hasMore = result.hasMore;
        _totalConversations = result.totalConversations;
        _isLoading = false;
        _isLoadingMore = false;
      });
      _syncUnreadBadgeFromConversations();
    } catch (e) {
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load conversations.',
        );
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: ChatService.unreadMessageCount,
            builder: (context, unreadCount, _) => TelegramTopBar(
              title: 'Inbox',
              subtitle: unreadCount > 0
                  ? 'Recent conversations - $unreadCount unread'
                  : 'Recent conversations',
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!AuthService.isLoggedIn) {
      return const TelegramSectionState.empty(
        title: 'Please login to view messages',
        subtitle: 'Login from the Account tab.',
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return TelegramSectionState.error(
        title: 'Failed to load messages',
        subtitle: _error,
        actionLabel: 'Retry',
        onAction: () => _loadConversations(forceRefresh: true),
      );
    }

    if (_conversations.isEmpty) {
      return const TelegramSectionState.empty(
        title: 'No messages yet',
        subtitle: 'Start chatting with property owners.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadConversations(forceRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _conversations.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _conversations.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return _ConversationTile(
            conversation: _conversations[index],
            onTap: () => _openConversation(_conversations[index]),
          );
        },
      ),
    );
  }

  Future<void> _openConversation(Conversation conversation) async {
    try {
      final isProductConversation = conversation.listingType == 'PRODUCT';
      final Rental? resolvedRental = isProductConversation
          ? Rental(
              id: -1,
              title: conversation.listingTitle ?? 'Marketplace Product',
              description: conversation.lastMessage ?? '',
              price: 0,
              address: conversation.listingTitle ?? 'Marketplace Product',
              city: '',
              state: '',
              bedrooms: 0,
              bathrooms: 0,
              squareFeet: 0,
              propertyType: 'OTHER',
            )
          : await RentalService.getById(conversation.rentalId);
      if (resolvedRental == null) {
        throw Exception('Listing is unavailable');
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            rental: resolvedRental,
            existingConversation: conversation,
          ),
        ),
      ).then((_) => _loadConversations(forceRefresh: true));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open conversation: $e')),
      );
    }
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id;
    final isOwner = conversation.ownerId == currentUserId;
    final otherName = isOwner ? conversation.userName : conversation.ownerName;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(otherName.isNotEmpty ? otherName[0].toUpperCase() : '?'),
        ),
        title: Text(
          otherName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              conversation.lastMessage ?? 'Open conversation',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if ((conversation.listingTitle ?? conversation.rentalTitle)
                .trim()
                .isNotEmpty)
              Text(
                conversation.listingTitle ?? conversation.rentalTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              conversation.lastMessageAt != null
                  ? _formatDate(conversation.lastMessageAt!)
                  : '',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (conversation.blockedByMe || conversation.blockedMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.block, size: 16, color: Colors.red[400]),
                  )
                else if (conversation.mutedByMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                  ),
                if (conversation.unreadCount > 0)
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      conversation.unreadCount > 99
                          ? '99+'
                          : '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
