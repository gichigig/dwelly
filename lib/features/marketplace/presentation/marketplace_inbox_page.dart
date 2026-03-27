import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/rental.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/auth_gate_card.dart';
import '../../listings/presentation/chat_page.dart';

class MarketplaceInboxPage extends StatefulWidget {
  final List<Conversation> initialConversations;

  const MarketplaceInboxPage({
    super.key,
    this.initialConversations = const <Conversation>[],
  });

  @override
  State<MarketplaceInboxPage> createState() => _MarketplaceInboxPageState();
}

class _MarketplaceInboxPageState extends State<MarketplaceInboxPage>
    with WidgetsBindingObserver {
  static const int _pageSize = 10;
  static const Duration _firstLoadTimeout = Duration(milliseconds: 4500);

  final ScrollController _scrollController = ScrollController();
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  String? _error;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    if (widget.initialConversations.isNotEmpty) {
      _conversations = List<Conversation>.from(widget.initialConversations);
      _isLoading = false;
      _hasMore = widget.initialConversations.length >= _pageSize;
    }
    _loadConversations(background: widget.initialConversations.isNotEmpty);
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
        listingType: 'PRODUCT',
        requestTimeout: _firstLoadTimeout,
      );
      if (!mounted) return;
      setState(() {
        _conversations = result.conversations;
        _hasMore = result.hasMore;
      });
    } catch (_) {}
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
      _loadConversations(loadMore: true);
    }
  }

  Future<void> _loadConversations({
    bool forceRefresh = false,
    bool loadMore = false,
    bool background = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _conversations = [];
        _currentPage = 0;
      });
      return;
    }

    if (loadMore && (_isLoadingMore || !_hasMore)) return;

    setState(() {
      _error = null;
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = !background && _conversations.isEmpty;
      }
    });

    try {
      final nextPage = loadMore ? _currentPage + 1 : 0;
      final result = await _fetchConversationsPage(
        page: nextPage,
        forceRefresh: forceRefresh,
        allowRetry: !loadMore && _conversations.isEmpty,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _conversations = [..._conversations, ...result.conversations];
        } else {
          _conversations = result.conversations;
        }
        _currentPage = result.page;
        _hasMore = result.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load marketplace inbox.',
        );
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<PaginatedConversations> _fetchConversationsPage({
    required int page,
    required bool forceRefresh,
    required bool allowRetry,
  }) async {
    try {
      return await ChatService.getConversationsPaginated(
        page: page,
        size: _pageSize,
        forceRefresh: forceRefresh,
        listingType: 'PRODUCT',
        requestTimeout: _firstLoadTimeout,
      );
    } catch (e) {
      if (!allowRetry) rethrow;
      await Future.delayed(const Duration(milliseconds: 320));
      return ChatService.getConversationsPaginated(
        page: page,
        size: _pageSize,
        forceRefresh: forceRefresh,
        listingType: 'PRODUCT',
        requestTimeout: _firstLoadTimeout,
      );
    }
  }

  Future<void> _openConversation(Conversation conversation) async {
    final pseudoRental = Rental(
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
      ownerId: conversation.ownerId > 0 ? conversation.ownerId : null,
      ownerName: conversation.ownerName,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatPage(rental: pseudoRental, existingConversation: conversation),
      ),
    );
    if (mounted) {
      _loadConversations(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AuthGateCard(
          title: 'Sign in to view marketplace chats',
          subtitle:
              'Your product buyer/seller conversations are available after login.',
          onSignIn: () => showLoginBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadConversations(forceRefresh: true);
            },
          ),
          onCreateAccount: () => showSignupBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadConversations(forceRefresh: true);
            },
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load marketplace inbox'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loadConversations(forceRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Text(
          'No marketplace conversations yet',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadConversations(forceRefresh: true),
      child: Column(
        children: [
          if (_error != null && _conversations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _InlineRetryBanner(
                message: _error!,
                onRetry: () => _loadConversations(forceRefresh: true),
              ),
            ),
          Expanded(
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
                final conversation = _conversations[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(_avatarLabel(conversation)),
                  ),
                  title: Text(
                    conversation.listingTitle ?? 'Marketplace Product',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    conversation.lastMessage ?? 'Open conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing:
                      conversation.unreadCount > 0 ||
                          conversation.mutedByMe ||
                          conversation.blockedByMe ||
                          conversation.blockedMe
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (conversation.blockedByMe ||
                                conversation.blockedMe)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.block,
                                  size: 16,
                                  color: Colors.red[400],
                                ),
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
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                child: Text(
                                  '${conversation.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        )
                      : null,
                  onTap: () => _openConversation(conversation),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _avatarLabel(Conversation conversation) {
    final title = (conversation.listingTitle ?? '').trim();
    if (title.isEmpty) return 'P';
    return title.substring(0, 1).toUpperCase();
  }
}

class _InlineRetryBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineRetryBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
