import 'dart:async';

import 'package:flutter/material.dart';

import 'core/navigation/app_tab_navigator.dart';
import 'core/models/advertisement.dart';
import 'core/services/ad_service.dart';
import 'core/services/app_notification_center.dart';
import 'core/services/auth_service.dart';
import 'core/services/chat_service.dart';
import 'core/widgets/ad_break_screen.dart';
import 'core/widgets/telegram/telegram_bottom_pill_nav.dart';
import 'core/widgets/telegram/telegram_fragment_item.dart';
import 'features/listings/presentation/account_page.dart';
import 'features/listings/presentation/donation_fab.dart';
import 'features/listings/presentation/explore_page.dart';
import 'features/listings/presentation/inbox_page.dart';
import 'features/listings/presentation/saved_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _isMarketplaceMode = false;
  AdService? _adService;
  bool _isResumeAdInFlight = false;
  Timer? _unreadBadgeTimer;
  final _savedPageKey = GlobalKey<SavedPageState>();
  final List<Widget?> _pages = List<Widget?>.filled(4, null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTabNavigator.requestedTab.addListener(_handleExternalTabRequest);
    _pages[0] = ExplorePage(
      onMarketplaceModeChanged: (active) =>
          setState(() => _isMarketplaceMode = active),
    );
    _startUnreadBadgePolling();
    unawaited(_initAdService());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTabNavigator.requestedTab.removeListener(_handleExternalTabRequest);
    _unreadBadgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAdService() async {
    try {
      final service = await AdService.getInstance();
      if (!mounted) return;
      setState(() => _adService = service);
    } catch (_) {
      // Ad service is optional.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_adService == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_adService!.markAppBackgrounded());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(AppNotificationCenter.reload());
      unawaited(_refreshUnreadBadge());
      unawaited(_maybeShowResumeAd());
    }
  }

  void _startUnreadBadgePolling() {
    unawaited(_refreshUnreadBadge());
    _unreadBadgeTimer?.cancel();
    _unreadBadgeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshUnreadBadge());
    });
  }

  Future<void> _refreshUnreadBadge() async {
    await ChatService.refreshUnreadMessageCount(forceRefresh: true);
  }

  Future<void> _maybeShowResumeAd() async {
    final service = _adService;
    if (!mounted || service == null || _isResumeAdInFlight) return;

    // Guard against interrupting transient flows (e.g. payment/passkey dialogs).
    final route = ModalRoute.of(context);
    final hasNestedRoute = Navigator.of(context, rootNavigator: true).canPop();
    if ((route != null && !route.isCurrent) || hasNestedRoute) {
      return;
    }

    final shouldShow = await service.shouldShowResumeAd();
    if (!shouldShow || !mounted) return;

    final config = await service.getDisplayConfig();
    if (!config.launchAdBreakEnabled || !mounted) return;

    final payload = await service.getAdBreak(
      AdPlacement.APP_LAUNCH,
      count: config.launchAdBreakCount.clamp(1, 2),
    );
    if (!mounted ||
        payload == null ||
        !payload.available ||
        payload.ads.isEmpty) {
      return;
    }

    _isResumeAdInFlight = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, _, __) => AdBreakScreen(
            ads: payload.ads,
            adService: service,
            placement: AdPlacement.APP_LAUNCH,
            firstAdUnskippable: config.launchAdFirstUnskippable,
            skipDelaySeconds: payload.policy.skipDelaySeconds,
            breakId: payload.breakId,
            markLaunchAdShownOnComplete: false,
            onComplete: () => Navigator.of(context).pop(),
          ),
          transitionsBuilder: (context, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      await service.markResumeAdShown();
    } finally {
      _isResumeAdInFlight = false;
    }
  }

  void _handleExternalTabRequest() {
    final requestedTab = AppTabNavigator.requestedTab.value;
    if (requestedTab == null) return;
    _navigateToTab(requestedTab);
    AppTabNavigator.clearRequest();
  }

  void _ensurePageLoaded(int index) {
    if (_pages[index] != null) return;

    switch (index) {
      case 0:
        _pages[index] = ExplorePage(
          onMarketplaceModeChanged: (active) =>
              setState(() => _isMarketplaceMode = active),
        );
        break;
      case 1:
        _pages[index] = SavedPage(key: _savedPageKey);
        break;
      case 2:
        _pages[index] = const InboxPage();
        break;
      case 3:
        _pages[index] = AccountPage(onNavigateToSaved: _navigateToSavedTab);
        break;
    }
  }

  void _navigateToSavedTab() {
    _navigateToTab(1, refreshSaved: true);
  }

  void _navigateToTab(int index, {bool refreshSaved = false}) {
    setState(() {
      _index = index;
      _ensurePageLoaded(index);
    });

    if (index == 2) {
      unawaited(_refreshUnreadBadge());
    }

    if (index == 1 && refreshSaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _savedPageKey.currentState?.refresh();
      });
    }
  }

  void _showLoginRequiredSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please sign in to donate'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Sign In',
          onPressed: () {
            setState(() => _index = 3); // Switch to Account tab
          },
        ),
      ),
    );
  }

  List<TelegramFragmentItem> _buildHomeTabs(int unreadInboxCount) {
    return [
      const TelegramFragmentItem(id: 'home', label: 'Home', icon: Icons.home),
      const TelegramFragmentItem(
        id: 'saved',
        label: 'Saved',
        icon: Icons.bookmark_border,
      ),
      TelegramFragmentItem(
        id: 'inbox',
        label: 'Inbox',
        icon: Icons.chat_bubble_outline,
        badgeCount: unreadInboxCount,
      ),
      const TelegramFragmentItem(
        id: 'account',
        label: 'Account',
        icon: Icons.person_outline,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // On Account tab, require auth for donation
    final isAccountTab = _index == 3;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          _pages.length,
          (i) => _pages[i] ?? const SizedBox.shrink(),
        ),
      ),
      floatingActionButton: _isMarketplaceMode
          ? null
          : DonationFab(
              requireAuth: isAccountTab,
              isAuthenticated: AuthService.isLoggedIn,
              onLoginRequired: _showLoginRequiredSnackBar,
            ),
      bottomNavigationBar: _isMarketplaceMode
          ? null
          : ValueListenableBuilder<int>(
              valueListenable: ChatService.unreadMessageCount,
              builder: (context, unreadInboxCount, _) {
                return TelegramBottomPillNav(
                  items: _buildHomeTabs(unreadInboxCount),
                  selectedIndex: _index,
                  onSelected: (i) {
                    _navigateToTab(i);
                    if (i == 1 && _savedPageKey.currentState != null) {
                      _savedPageKey.currentState?.refresh();
                    }
                  },
                );
              },
            ),
    );
  }
}
