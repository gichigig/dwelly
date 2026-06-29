import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/widgets/full_screen_image_avatar.dart';
import '../../user_profile/presentation/user_public_profile_page.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/rental.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/services/group_service.dart';
import '../../../core/services/chat_realtime_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/models/chat_group.dart';
import '../../../core/widgets/create_group_dialog.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/telegram/telegram_section_state.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import 'chat_page.dart';
import 'group_chat_page.dart';
import 'contacts_list_page.dart';
import 'house_search_help_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => InboxPageState();
}

class InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  static const int _pageSize = 10;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Conversation> _conversations = [];
  List<ChatGroup> _groups = [];

  List<dynamic> _filteredInboxItems = [];

  void _updateFilteredItems() {
    var items = <dynamic>[..._conversations, ..._groups];

    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        if (item is Conversation) {
          final userName = item.userName.toLowerCase();
          final ownerName = item.ownerName.toLowerCase();
          final userHandle = item.userUsername?.toLowerCase() ?? '';
          final ownerHandle = item.ownerUsername?.toLowerCase() ?? '';
          final listingTitle = item.listingTitle?.toLowerCase() ?? '';
          final rentalTitle = item.rentalTitle.toLowerCase();
          final lastMessage = item.lastMessage?.toLowerCase() ?? '';
          return userName.contains(_searchQuery) ||
                 ownerName.contains(_searchQuery) ||
                 userHandle.contains(_searchQuery) ||
                 ownerHandle.contains(_searchQuery) ||
                 listingTitle.contains(_searchQuery) ||
                 rentalTitle.contains(_searchQuery) ||
                 lastMessage.contains(_searchQuery);
        } else if (item is ChatGroup) {
          final name = item.name.toLowerCase();
          final lastMessage = item.lastMessage?.toLowerCase() ?? '';
          return name.contains(_searchQuery) || lastMessage.contains(_searchQuery);
        }
        return false;
      }).toList();
    }

    items.sort((a, b) {
      final aTime = _getTime(a);
      final bTime = _getTime(b);
      return bTime.compareTo(aTime);
    });
    _filteredInboxItems = items;
  }

  DateTime _getTime(dynamic item) {
    if (item is Conversation) {
      return item.lastMessageAt ?? item.createdAt;
    } else if (item is ChatGroup) {
      return item.lastMessageAt ?? item.createdAt;
    }
    return DateTime.now();
  }
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  int _totalConversations = 0;
  int _groupPage = 0;
  bool _groupHasMore = false;
  String? _error;
  Timer? _pollingTimer;
  bool _hasPendingHouseSearchRequest = false;
  String? _houseSearchRequestSummary;
  final _realtimeService = ChatRealtimeService();

  void _syncUnreadBadgeFromConversations() {
    ChatService.unreadMessageCount.value = _conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );
    // Note: Group unread counts can be added here if needed
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    NotificationService.clearMessageNotifications();
    _loadHouseSearchRequest();
    _loadConversations();
    _startPolling();

    final currentUser = AuthService.currentUser;
    if (currentUser != null && currentUser.id != null) {
      _realtimeService.connect(
        onConnected: () {
          _realtimeService.subscribeUserGroups(
            currentUser.id!,
            (newGroup) {
              if (!mounted) return;
              setState(() {
                final exists = _groups.any((g) => g.id == newGroup.id);
                if (!exists) {
                  _groups.add(newGroup);
                  _updateFilteredItems();
                }
              });
            },
          );
        },
        onError: (error) {},
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    _pollingTimer?.cancel();
    _realtimeService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadHouseSearchRequest();
      _loadConversations(forceRefresh: true);
    }
  }

  void _startPolling() {
    // Poll for conversation updates every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollForUpdates();
    });
  }

  Future<void> _loadHouseSearchRequest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hasPendingHouseSearchRequest =
          prefs.getBool(HouseSearchHelpPage.pendingRequestKey) ?? false;
      _houseSearchRequestSummary = prefs.getString(
        'house_search_helper_request_summary_v1',
      );
    });
  }

  Future<void> _clearHouseSearchRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(HouseSearchHelpPage.pendingRequestKey);
    await prefs.remove('house_search_helper_request_summary_v1');
    if (!mounted) return;
    setState(() {
      _hasPendingHouseSearchRequest = false;
      _houseSearchRequestSummary = null;
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
        
        // Polling groups
        GroupService.getMyGroups(page: 0, limit: _pageSize).then((groupData) {
          if (mounted) {
            setState(() {
              final latestGroups = groupData['groups'] as List<ChatGroup>;
              if (_groups.length <= _pageSize) {
                _groups = latestGroups;
              } else {
                final trailing = _groups.skip(_pageSize);
                _groups = [...latestGroups, ...trailing];
              }
              _groupHasMore = groupData['hasMore'] as bool || _groups.length < _pageSize;
              _updateFilteredItems();
            });
          }
        }).catchError((_) {});
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

  Future<void> refresh() async {
    return _loadConversations(forceRefresh: true);
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
        _groups = [];
        _isLoadingMore = false;
        _hasMore = false;
        _currentPage = 0;
        _totalConversations = 0;
        _groupPage = 0;
        _groupHasMore = false;
        _updateFilteredItems();
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
      final nextGroupPage = loadMore ? _groupPage + 1 : 0;
      
      final results = await Future.wait([
        if (!loadMore || _hasMore) ChatService.getConversationsPaginated(
          page: nextPage,
          size: _pageSize,
          forceRefresh: forceRefresh,
        ),
        if (!loadMore || _groupHasMore) GroupService.getMyGroups(
          page: nextGroupPage, 
          limit: _pageSize
        ),
      ]);

      PaginatedConversations? convResult;
      Map<String, dynamic>? groupResult;
      
      for (final result in results) {
        if (result is PaginatedConversations) {
          convResult = result;
        } else if (result is Map<String, dynamic>) {
          groupResult = result;
        }
      }

      setState(() {
        if (convResult != null) {
          if (loadMore) {
            _conversations = [..._conversations, ...convResult.conversations];
          } else {
            _conversations = convResult.conversations;
          }
          _currentPage = convResult.page;
          _hasMore = convResult.hasMore;
          _totalConversations = convResult.totalConversations;
        }
        
        if (groupResult != null) {
          final newGroups = groupResult['groups'] as List<ChatGroup>;
          if (loadMore) {
            _groups = [..._groups, ...newGroups];
          } else {
            _groups = newGroups;
          }
          _groupPage = groupResult['page'] as int;
          _groupHasMore = groupResult['hasMore'] as bool;
        }

        _isLoading = false;
        _isLoadingMore = false;
        _updateFilteredItems();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                          _updateFilteredItems();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search chats...',
                        prefixIcon: Icon(
                          Icons.search,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _updateFilteredItems();
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.group_add,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    onPressed: () async {
                      if (!AuthService.isLoggedIn) {
                        showLoginBottomSheet(context, onSuccess: () {
                          // Allow user to try again after login
                        });
                        return;
                      }
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => CreateGroupDialog(),
                      );
                      
                      if (result == null || result['name'] == null || (result['name'] as String).isEmpty) return;
                      
                      final name = result['name'] as String;
                      final buildingId = result['buildingId'] as int?;
                      
                      try {
                        final newGroup = await GroupService.createGroup(name, buildingId: buildingId);
                        if (mounted) {
                          _loadConversations(forceRefresh: true);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupChatPage(group: newGroup),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to create group: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ContactsListPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
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
      return Column(
        children: [
          if (_hasPendingHouseSearchRequest)
            _HouseSearchRequestCard(
              summary: _houseSearchRequestSummary,
              onDismiss: _clearHouseSearchRequest,
            ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_error != null) {
      return Column(
        children: [
          if (_hasPendingHouseSearchRequest)
            _HouseSearchRequestCard(
              summary: _houseSearchRequestSummary,
              onDismiss: _clearHouseSearchRequest,
            ),
          Expanded(
            child: TelegramSectionState.error(
              title: 'Failed to load messages',
              subtitle: _error,
              actionLabel: 'Retry',
              onAction: () => _loadConversations(forceRefresh: true),
            ),
          ),
        ],
      );
    }

    if (_filteredInboxItems.isEmpty && _searchQuery.isEmpty) {
      return Column(
        children: [
          if (_hasPendingHouseSearchRequest)
            _HouseSearchRequestCard(
              summary: _houseSearchRequestSummary,
              onDismiss: _clearHouseSearchRequest,
            ),
          const Expanded(
            child: TelegramSectionState.empty(
              title: 'No messages yet',
              subtitle: 'Start chatting with property owners and helpers.',
            ),
          ),
        ],
      );
    }

    if (_filteredInboxItems.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No results found',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_hasPendingHouseSearchRequest)
          _HouseSearchRequestCard(
            summary: _houseSearchRequestSummary,
            onDismiss: _clearHouseSearchRequest,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadHouseSearchRequest();
              await _loadConversations(forceRefresh: true);
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              controller: _scrollController,
              itemCount: _filteredInboxItems.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _filteredInboxItems.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final item = _filteredInboxItems[index];
                if (item is Conversation) {
                  return _ConversationTile(
                    conversation: item,
                    onTap: () => _openConversation(item),
                    onLongPress: () => _deleteConversation(item),
                  );
                } else if (item is ChatGroup) {
                  return _GroupTile(
                    group: item,
                    onTap: () => _openGroup(item),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openConversation(Conversation conversation) async {
    try {
      final isProductConversation = conversation.listingType == 'PRODUCT';
      final isPeerToPeer = conversation.listingType == 'PEER_TO_PEER' || conversation.rentalId == null || conversation.rentalId == 0;
      
      final Rental? resolvedRental;
      
      if (isProductConversation) {
        resolvedRental = Rental(
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
          ownerAvatarUrl: conversation.ownerAvatarUrl,
        );
      } else if (isPeerToPeer) {
        resolvedRental = Rental(
          id: conversation.rentalId ?? 0,
          ownerId: conversation.ownerId,
          title: conversation.listingTitle ?? 'Direct Message',
          description: conversation.lastMessage ?? '',
          price: 0,
          address: conversation.listingTitle ?? 'Direct Message',
          city: '',
          state: '',
          bedrooms: 0,
          bathrooms: 0,
          squareFeet: 0,
          propertyType: 'OTHER',
          ownerAvatarUrl: conversation.ownerAvatarUrl,
        );
      } else {
        resolvedRental = await RentalService.getById(conversation.rentalId);
      }

      if (resolvedRental == null) {
        throw Exception('Listing is unavailable');
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            rental: resolvedRental!,
            existingConversation: conversation,
          ),
        ),
      ).then((_) {
        _loadHouseSearchRequest();
        _loadConversations(forceRefresh: true);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open conversation: $e')),
      );
    }
  }

  void _openGroup(ChatGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatPage(group: group),
      ),
    ).then((_) {
      _loadHouseSearchRequest();
      _loadConversations(forceRefresh: true);
    });
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('Are you sure you want to delete this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && conversation.id != null) {
      if (!mounted) return;
      try {
        await ChatService.deleteConversation(conversation.id!);
        _loadConversations(forceRefresh: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conversation deleted')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

class _HouseSearchRequestCard extends StatelessWidget {
  final String? summary;
  final VoidCallback onDismiss;

  const _HouseSearchRequestCard({this.summary, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = summary == null || summary!.trim().isEmpty
        ? 'House search helper request'
        : summary!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Material(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.support_agent, color: colorScheme.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'When a helper accepts, the chat will appear here.',
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss request',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ConversationTile({required this.conversation, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id;
    final isOwner = conversation.ownerId == currentUserId;
    final otherName = isOwner ? conversation.userName : conversation.ownerName;
    String? otherAvatarUrl = isOwner ? conversation.userAvatarUrl : conversation.ownerAvatarUrl;

    if (otherAvatarUrl == null || otherAvatarUrl.isEmpty) {
      try {
        final contactId = isOwner ? conversation.userId : conversation.ownerId;
        final contact = ContactService.contacts.value.firstWhere(
          (c) => c.contactUserId == contactId,
        );
        otherAvatarUrl = contact.avatarUrl;
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  final otherId = isOwner ? conversation.userId : conversation.ownerId;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserPublicProfilePage(userId: otherId),
                    ),
                  );
                },
                child: FullScreenImageAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  avatarUrl: otherAvatarUrl,
                  fallbackWidget: Text(
                    otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.lastMessage ?? 'Open conversation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    if ((conversation.listingTitle ?? conversation.rentalTitle).trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          conversation.listingTitle ?? conversation.rentalTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
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
                  const SizedBox(height: 8),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
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
            ],
          ),
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

class _GroupTile extends StatelessWidget {
  final ChatGroup group;
  final VoidCallback onTap;

  const _GroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _showGroupDetails(context),
                child: FullScreenImageAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.tertiary,
                  avatarUrl: group.avatarUrl,
                  fallbackWidget: const Icon(Icons.group, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'GROUP',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    group.lastMessageAt != null
                        ? _formatDate(group.lastMessageAt!)
                        : '',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGroupDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (group.description != null && group.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  group.description!,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: group.members.length,
                  itemBuilder: (context, index) {
                    final member = group.members[index];
                    final displayName = '${member.firstName} ${member.lastName}';
                    return ListTile(
                      leading: FullScreenImageAvatar(
                        avatarUrl: member.userAvatar,
                        fallbackWidget: Text(member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '?'),
                      ),
                      title: Text(displayName),
                      subtitle: Text(member.role),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserPublicProfilePage(userId: member.userId),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
