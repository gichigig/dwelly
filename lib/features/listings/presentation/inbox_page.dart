import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/widgets/dwelly_orbiting_loader.dart';
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
import '../../lost_id/data/id_scanner_service.dart';
import '../../lost_id/presentation/temporary_chat_page.dart';

class TemporaryChatSummary {
  final int id;
  final String roomId;
  final int foundIdId;
  final String finderAlias;
  final String ownerAlias;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String myRole;
  final String lastMessageContent;

  TemporaryChatSummary({
    required this.id,
    required this.roomId,
    required this.foundIdId,
    required this.finderAlias,
    required this.ownerAlias,
    required this.createdAt,
    required this.lastMessageAt,
    required this.myRole,
    required this.lastMessageContent,
  });

  factory TemporaryChatSummary.fromJson(Map<String, dynamic> json) {
    return TemporaryChatSummary(
      id: json['id'] ?? 0,
      roomId: json['roomId']?.toString() ?? '',
      foundIdId: json['foundIdId'] ?? 0,
      finderAlias: json['finderAlias']?.toString() ?? 'Finder',
      ownerAlias: json['ownerAlias']?.toString() ?? 'Owner',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now()
          : DateTime.now(),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.tryParse(json['lastMessageAt']?.toString() ?? '') ??
                DateTime.now()
          : DateTime.now(),
      myRole: json['myRole']?.toString() ?? 'OWNER',
      lastMessageContent: json['lastMessageContent']?.toString() ?? '',
    );
  }

  String get displayOtherAlias =>
      myRole.toUpperCase() == 'FINDER' ? ownerAlias : finderAlias;
}

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
  List<TemporaryChatSummary> _temporaryChats = [];

  List<dynamic> _filteredInboxItems = [];

  void _updateFilteredItems() {
    var items = <dynamic>[..._conversations, ..._groups, ..._temporaryChats];

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
          return name.contains(_searchQuery) ||
              lastMessage.contains(_searchQuery);
        } else if (item is TemporaryChatSummary) {
          final alias = item.displayOtherAlias.toLowerCase();
          final lastMessage = item.lastMessageContent.toLowerCase();
          return alias.contains(_searchQuery) ||
              lastMessage.contains(_searchQuery) ||
              'anonymous'.contains(_searchQuery) ||
              'lost id'.contains(_searchQuery);
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
    } else if (item is TemporaryChatSummary) {
      return item.lastMessageAt;
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
  final Map<int, bool> _typingStatus = {};
  final Map<int, Timer> _typingTimers = {};

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
    _loadHouseSearchRequest();
    _loadConversations();
    _startPolling();

    final currentUser = AuthService.currentUser;
    if (currentUser != null && currentUser.id != null) {
      _realtimeService.connect(
        onConnected: () {
          _realtimeService.subscribeUserGroups(currentUser.id!, (newGroup) {
            if (!mounted) return;
            setState(() {
              final exists = _groups.any((g) => g.id == newGroup.id);
              if (!exists) {
                _groups.add(newGroup);
                _updateFilteredItems();
              }
            });
          });

          _realtimeService.subscribeUserTyping(currentUser.id!, (event) {
            if (!mounted) return;
            setState(() {
              _typingStatus[event.conversationId] = event.isTyping;
            });
            _typingTimers[event.conversationId]?.cancel();
            if (event.isTyping) {
              _typingTimers[event.conversationId] = Timer(const Duration(seconds: 4), () {
                if (mounted && _typingStatus[event.conversationId] == true) {
                  setState(() => _typingStatus[event.conversationId] = false);
                }
              });
            }
          });
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
        GroupService.getMyGroups(page: 0, limit: _pageSize)
            .then((groupData) {
              if (mounted) {
                setState(() {
                  final latestGroups = groupData['groups'] as List<ChatGroup>;
                  if (_groups.length <= _pageSize) {
                    _groups = latestGroups;
                  } else {
                    final trailing = _groups.skip(_pageSize);
                    _groups = [...latestGroups, ...trailing];
                  }
                  _groupHasMore =
                      groupData['hasMore'] as bool ||
                      _groups.length < _pageSize;
                  _updateFilteredItems();
                });
              }
            })
            .catchError((_) {});

        // Polling temporary chats
        IdScannerServiceChat.getMyTemporaryChats()
            .then((list) {
              if (mounted) {
                setState(() {
                  _temporaryChats = list
                      .map((e) => TemporaryChatSummary.fromJson(e))
                      .toList();
                  _updateFilteredItems();
                });
              }
            })
            .catchError((_) {});
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
        _isLoading = _conversations.isEmpty && _groups.isEmpty;
      }
    });

    try {
      final nextPage = loadMore ? _currentPage + 1 : 0;
      final nextGroupPage = loadMore ? _groupPage + 1 : 0;

      final results = await Future.wait([
        if (!loadMore || _hasMore)
          ChatService.getConversationsPaginated(
            page: nextPage,
            size: _pageSize,
            forceRefresh: forceRefresh,
          ).catchError((e) {
            if (_conversations.isNotEmpty) {
              return PaginatedConversations(
                conversations: _conversations,
                hasMore: _hasMore,
                page: _currentPage,
                size: _pageSize,
                totalConversations: _totalConversations,
              );
            }
            throw e;
          }),
        if (!loadMore || _groupHasMore)
          GroupService.getMyGroups(
            page: nextGroupPage,
            limit: _pageSize,
            forceRefresh: forceRefresh,
          ).catchError((e) {
            return {
              'groups': _groups,
              'hasMore': _groupHasMore,
              'page': _groupPage,
            };
          }),
        if (!loadMore)
          IdScannerServiceChat.getMyTemporaryChats().catchError(
            (e) => <Map<String, dynamic>>[],
          ),
      ]);

      PaginatedConversations? convResult;
      Map<String, dynamic>? groupResult;
      List<TemporaryChatSummary>? tempResult;

      for (final result in results) {
        if (result is PaginatedConversations) {
          convResult = result;
        } else if (result is Map<String, dynamic>) {
          groupResult = result;
        } else if (result is List<Map<String, dynamic>>) {
          tempResult = result
              .map((e) => TemporaryChatSummary.fromJson(e))
              .toList();
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

        if (tempResult != null) {
          _temporaryChats = tempResult;
        }

        _isLoading = false;
        _isLoadingMore = false;
        _updateFilteredItems();
      });
      _syncUnreadBadgeFromConversations();
    } catch (e) {
      setState(() {
        if (_conversations.isEmpty && _groups.isEmpty) {
          _error = userErrorMessage(
            e,
            fallbackMessage: 'Failed to load conversations.',
          );
        } else {
          _error = null;
        }
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
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
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
                        showLoginBottomSheet(
                          context,
                          onSuccess: () {
                            // Allow user to try again after login
                          },
                        );
                        return;
                      }
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => CreateGroupDialog(),
                      );

                      if (result == null ||
                          result['name'] == null ||
                          (result['name'] as String).isEmpty)
                        return;

                      final name = result['name'] as String;
                      final buildingId = result['buildingId'] as int?;

                      try {
                        final newGroup = await GroupService.createGroup(
                          name,
                          buildingId: buildingId,
                        );
                        if (mounted) {
                          setState(() {
                            if (!_groups.any((g) => g.id == newGroup.id)) {
                              _groups.insert(0, newGroup);
                              _updateFilteredItems();
                            }
                          });
                          _loadConversations(forceRefresh: true);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  GroupChatPage(group: newGroup),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to create group: $e'),
                            ),
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
            MaterialPageRoute(builder: (context) => ContactsListPage()),
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

    if (_isLoading && _conversations.isEmpty && _groups.isEmpty) {
      return Column(
        children: [
          if (_hasPendingHouseSearchRequest)
            _HouseSearchRequestCard(
              summary: _houseSearchRequestSummary,
              onDismiss: _clearHouseSearchRequest,
            ),
          const Expanded(child: Center(child: DwellyOrbitingLoader())),
        ],
      );
    }

    if (_error != null && _conversations.isEmpty && _groups.isEmpty) {
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
              padding: const EdgeInsets.only(bottom: 100),
              controller: _scrollController,
              itemCount: _filteredInboxItems.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _filteredInboxItems.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: DwellyOrbitingLoader()),
                  );
                }

                final item = _filteredInboxItems[index];
                if (item is Conversation) {
                  return _ConversationTile(
                    conversation: item,
                    isTyping: _typingStatus[item.id] ?? false,
                    onTap: () => _openConversation(item),
                    onLongPress: () => _deleteConversation(item),
                  );
                } else if (item is ChatGroup) {
                  return _GroupTile(group: item, onTap: () => _openGroup(item));
                } else if (item is TemporaryChatSummary) {
                  return _TemporaryChatTile(
                    summary: item,
                    onTap: () => _openTemporaryChat(item),
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
      final isPeerToPeer =
          conversation.listingType == 'PEER_TO_PEER' ||
          conversation.rentalId == null ||
          conversation.rentalId == 0;

      final Rental? resolvedRental;

      if (isPeerToPeer) {
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
      if (conversation.id != null) {
        ChatService.markConversationAsReadLocal(conversation.id!);
        final idx = _conversations.indexWhere((c) => c.id == conversation.id);
        if (idx >= 0 && _conversations[idx].unreadCount > 0) {
          setState(() {
            _conversations[idx] = Conversation(
              id: _conversations[idx].id,
              listingType: _conversations[idx].listingType,
              listingId: _conversations[idx].listingId,
              listingTitle: _conversations[idx].listingTitle,
              listingImageUrl: _conversations[idx].listingImageUrl,
              rentalId: _conversations[idx].rentalId,
              rentalTitle: _conversations[idx].rentalTitle,
              userId: _conversations[idx].userId,
              userName: _conversations[idx].userName,
              userUsername: _conversations[idx].userUsername,
              ownerId: _conversations[idx].ownerId,
              ownerName: _conversations[idx].ownerName,
              ownerUsername: _conversations[idx].ownerUsername,
              mutedByMe: _conversations[idx].mutedByMe,
              blockedByMe: _conversations[idx].blockedByMe,
              blockedMe: _conversations[idx].blockedMe,
              lastMessage: _conversations[idx].lastMessage,
              lastMessageAt: _conversations[idx].lastMessageAt,
              unreadCount: 0,
              createdAt: _conversations[idx].createdAt,
            );
          });
          _syncUnreadBadgeFromConversations();
        }
      }
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
      MaterialPageRoute(builder: (context) => GroupChatPage(group: group)),
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
        content: const Text(
          'Are you sure you want to delete this conversation?',
        ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Conversation deleted')));
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  void _openTemporaryChat(TemporaryChatSummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TemporaryChatPage(
          roomId: summary.roomId,
          myRole: summary.myRole,
          myAlias: summary.myRole.toUpperCase() == 'FINDER'
              ? summary.finderAlias
              : summary.ownerAlias,
          otherAlias: summary.displayOtherAlias,
        ),
      ),
    ).then((_) => _loadConversations(forceRefresh: true));
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
  final bool isTyping;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ConversationTile({
    required this.conversation,
    this.isTyping = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id;
    final isOwner = conversation.ownerId == currentUserId;
    final otherName = isOwner ? conversation.userName : conversation.ownerName;
    String? otherAvatarUrl = isOwner
        ? conversation.userAvatarUrl
        : conversation.ownerAvatarUrl;

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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0),
        side: BorderSide.none,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                  final otherId = isOwner
                      ? conversation.userId
                      : conversation.ownerId;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserPublicProfilePage(userId: otherId),
                    ),
                  );
                },
                child: FullScreenImageAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    isTyping
                        ? Text(
                            'typing...',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : Row(
                            children: [
                              if (conversation.lastMessageSenderId == currentUserId)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.done_all,
                                    size: 16,
                                    color: conversation.lastMessageIsRead == true
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _formatInboxPreview(
                                    conversation.lastMessage,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    if ((conversation.listingTitle ?? conversation.rentalTitle)
                        .trim()
                        .isNotEmpty)
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
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

  String _formatInboxPreview(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Open conversation';
    }

    final trimmed = rawMessage.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return rawMessage;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final hasContactShape =
            decoded.containsKey('name') && decoded.containsKey('phone');
        if (hasContactShape) {
          return 'Contact sent';
        }
      }
    } catch (_) {
      // Keep the original message if it's not valid JSON.
    }

    return rawMessage;
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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0),
        side: BorderSide.none,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'GROUP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (group.description != null &&
                  group.description!.isNotEmpty) ...[
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
                    final displayName =
                        '${member.firstName} ${member.lastName}';
                    return ListTile(
                      leading: FullScreenImageAvatar(
                        avatarUrl: member.userAvatar,
                        fallbackWidget: Text(
                          member.firstName.isNotEmpty
                              ? member.firstName[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(displayName),
                      subtitle: Text(member.role),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                UserPublicProfilePage(userId: member.userId),
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

class _TemporaryChatTile extends StatelessWidget {
  final TemporaryChatSummary summary;
  final VoidCallback onTap;

  const _TemporaryChatTile({required this.summary, required this.onTap});

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      final hour = time.hour > 12
          ? time.hour - 12
          : (time.hour == 0 ? 12 : time.hour);
      final period = time.hour >= 12 ? 'PM' : 'AM';
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.month}/${time.day}/${time.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.blue.shade100,
              child: Icon(
                Icons.shield_outlined,
                color: Colors.blue.shade700,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${summary.displayOtherAlias} • 🔒 Anonymous ID Chat',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(summary.lastMessageAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Expires in 7d',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          summary.lastMessageContent.isEmpty
                              ? 'Tap to start anonymous conversation...'
                              : summary.lastMessageContent,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
