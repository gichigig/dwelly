import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/widgets/telegram/telegram_bottom_pill_nav.dart';
import '../../../core/widgets/telegram/telegram_fragment_item.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import 'marketplace_account_page.dart';
import 'marketplace_inbox_page.dart';
import 'marketplace_saved_page.dart';
import 'marketplace_seller_dashboard_page.dart';
import 'marketplace_view.dart';

class MarketplaceShellPage extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const MarketplaceShellPage({super.key, this.onBackToHome});

  @override
  State<MarketplaceShellPage> createState() => _MarketplaceShellPageState();
}

class _MarketplaceShellPageState extends State<MarketplaceShellPage>
    with WidgetsBindingObserver {
  int _index = 0;
  final List<Widget?> _fragments = List<Widget?>.filled(6, null);
  MarketplaceTabPreviews _tabPreviews = const MarketplaceTabPreviews();
  MarketplaceAccountSummary _accountSummary =
      const MarketplaceAccountSummary.empty();
  bool _isBadgeLoading = true;
  bool _prefetchDone = false;

  static const List<String> _sectionNames = [
    'Home',
    'Search',
    'Saved',
    'Sell',
    'Inbox',
    'Account',
  ];

  static const List<TelegramFragmentItem> _items = [
    TelegramFragmentItem(id: 'home', label: 'Home', icon: Icons.home),
    TelegramFragmentItem(id: 'search', label: 'Search', icon: Icons.search),
    TelegramFragmentItem(
      id: 'saved',
      label: 'Saved',
      icon: Icons.bookmark_border,
    ),
    TelegramFragmentItem(
      id: 'sell',
      label: 'Sell',
      icon: Icons.storefront_outlined,
    ),
    TelegramFragmentItem(
      id: 'inbox',
      label: 'Inbox',
      icon: Icons.chat_bubble_outline,
    ),
    TelegramFragmentItem(
      id: 'account',
      label: 'Account',
      icon: Icons.person_outline,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureLoaded(0);
    // Don't call bootstrap here — MarketplaceView handles it.
    // Defer tab data prefetch so it doesn't compete with product loading.
    _deferPrefetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_loadTabBadges());
  }

  void _switchTo(int next) {
    if (_index == next) return;
    setState(() {
      _index = next;
      _ensureLoaded(next);
    });
    if (next >= 2) {
      unawaited(_loadTabBadges());
    }
  }

  void _deferPrefetch() {
    // Wait 3 seconds so the main product load completes first,
    // then prefetch tab data and badges in the background.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || _prefetchDone) return;
      _prefetchDone = true;
      unawaited(_loadTabBadges());
      unawaited(_prefetchTabData());
    });
  }

  Future<void> _prefetchTabData() async {
    if (!AuthService.isLoggedIn) return;
    const timeout = Duration(seconds: 8);
    try {
      await Future.wait([
        MarketplaceService.getSavedProducts(
          page: 0,
          size: 10,
          requestTimeout: timeout,
        ),
        MarketplaceService.getMyProducts(
          page: 0,
          size: 20,
          requestTimeout: timeout,
        ),
        ChatService.getConversationsPaginated(
          page: 0,
          size: 10,
          listingType: 'PRODUCT',
          requestTimeout: timeout,
        ),
        MarketplaceService.getAccountSummary(requestTimeout: timeout),
      ], eagerError: false);
    } catch (_) {
      // Warmup failures are non-blocking.
    }
  }

  void _ensureLoaded(int index) {
    if (_fragments[index] != null) return;
    final user = AuthService.currentUser;
    switch (index) {
      case 0:
        _fragments[index] = MarketplaceView(
          defaultCounty: user?.locationCounty,
          defaultConstituency: user?.locationConstituency,
          defaultWard: user?.locationWard,
          mode: MarketplaceViewMode.home,
        );
        break;
      case 1:
        _fragments[index] = MarketplaceView(
          defaultCounty: user?.locationCounty,
          defaultConstituency: user?.locationConstituency,
          defaultWard: user?.locationWard,
          mode: MarketplaceViewMode.search,
        );
        break;
      case 2:
        _fragments[index] = MarketplaceSavedPage(
          initialProducts: _tabPreviews.savedProducts,
        );
        break;
      case 3:
        _fragments[index] = MarketplaceSellerDashboardPage(
          initialProducts: _tabPreviews.myProducts,
        );
        break;
      case 4:
        _fragments[index] = MarketplaceInboxPage(
          initialConversations: _tabPreviews.inboxConversations,
        );
        break;
      case 5:
        _fragments[index] = MarketplaceAccountPage(
          initialSummary: _accountSummary.authenticated
              ? _accountSummary
              : null,
        );
        break;
    }
  }

  Future<void> _loadTabBadges() async {
    if (!mounted) return;
    if (!AuthService.isLoggedIn) {
      setState(() {
        _accountSummary = const MarketplaceAccountSummary.empty();
        _isBadgeLoading = false;
      });
      return;
    }

    if (!_isBadgeLoading) {
      setState(() => _isBadgeLoading = true);
    }

    try {
      final summary = await MarketplaceService.getAccountSummary(
        requestTimeout: const Duration(seconds: 4),
      );
      if (!mounted) return;
      setState(() {
        _accountSummary = summary;
        _isBadgeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBadgeLoading = false);
    }
  }

  int _badgeForTab(int tabIndex) {
    if (_isBadgeLoading || !_accountSummary.authenticated) {
      return 0;
    }
    return switch (tabIndex) {
      2 => _accountSummary.savedCount,
      3 => _accountSummary.activeProducts,
      4 => _accountSummary.inboxUnreadCount,
      _ => 0,
    };
  }

  List<TelegramFragmentItem> _buildNavItems() {
    return List<TelegramFragmentItem>.generate(_items.length, (index) {
      final item = _items[index];
      return TelegramFragmentItem(
        id: item.id,
        label: item.label,
        icon: item.icon,
        badgeCount: _badgeForTab(index),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TelegramTopBar(
            title: 'Marketplace',
            subtitle: '${_sectionNames[_index]} section',
            leadingIcon: widget.onBackToHome != null ? Icons.swap_horiz : null,
            leadingTooltip: 'Back to Find Your Home',
            onLeadingTap: widget.onBackToHome,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  _prefetchDone = false;
                  _fragments[_index] = null;
                  _ensureLoaded(_index);
                  _deferPrefetch();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: List<Widget>.generate(
                _fragments.length,
                (i) => _fragments[i] ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TelegramBottomPillNav(
        items: _buildNavItems(),
        selectedIndex: _index,
        onSelected: _switchTo,
      ),
    );
  }
}
