import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/navigation/app_tab_navigator.dart';
import 'core/models/advertisement.dart';
import 'core/services/ad_service.dart';
import 'core/services/app_notification_center.dart';
import 'core/services/auth_service.dart';
import 'core/services/chat_service.dart';
import 'core/services/premium_service.dart';
import 'core/services/google_ad_service.dart';
import 'core/widgets/ad_break_screen.dart';
import 'core/widgets/telegram/telegram_bottom_pill_nav.dart';
import 'core/widgets/telegram/telegram_fragment_item.dart';
import 'features/listings/presentation/account_page.dart';
import 'features/listings/presentation/explore_page.dart';
import 'features/listings/presentation/inbox_page.dart';
import 'features/listings/presentation/premium_launch_screen.dart';
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
  bool _premiumLaunchShown = false;
  final _savedPageKey = GlobalKey<SavedPageState>();
  final _explorePageKey = GlobalKey<ExplorePageState>();
  final _inboxPageKey = GlobalKey<InboxPageState>();
  final List<Widget?> _pages = List<Widget?>.filled(4, null);
  
  bool _showBottomNav = true;
  Offset? _pointerDownPosition;

  // Navigation history for back button
  final List<int> _tabHistory = [0];
  DateTime? _lastBackPressTime;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      if (notification is ScrollUpdateNotification) {
        final delta = notification.scrollDelta ?? 0;
        if (delta > 5.0 && _showBottomNav) {
          setState(() => _showBottomNav = false);
        } else if (delta < -5.0 && !_showBottomNav) {
          setState(() => _showBottomNav = true);
        }
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTabNavigator.requestedTab.addListener(_handleExternalTabRequest);
    if (AuthService.isTenantMode) {
      _index = 0;
      _pages[0] = InboxPage(key: _inboxPageKey);
    } else {
      _pages[0] = ExplorePage(
        onMarketplaceModeChanged: (active) =>
            setState(() => _isMarketplaceMode = active),
      );
    }
    _startUnreadBadgePolling();
    unawaited(_initAdService());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowPremiumLaunch());
    });
    // Fetch fresh profile on cold boot in case user upgraded out-of-band or was upgraded in a previous session
    if (AuthService.isLoggedIn) {
      unawaited(PremiumService.refreshPremiumStatus().then((_) {
        if (mounted) setState(() {});
      }));
    }
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
      unawaited(PremiumService.refreshPremiumStatus().then((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  void _startUnreadBadgePolling() {
    unawaited(_refreshUnreadBadge());
    _unreadBadgeTimer?.cancel();
    _unreadBadgeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshUnreadBadge());
    });
  }

  Future<void> _maybeShowPremiumLaunch() async {
    if (!mounted || _premiumLaunchShown) return;
    if (PremiumService.isPremiumActive() || !PremiumService.isPremiumPageVisible()) return;
    _premiumLaunchShown = true;

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, _, __) => const PremiumLaunchScreen(),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
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

    if (AuthService.isTenantMode) {
      switch (index) {
        case 0:
          _pages[index] = InboxPage(key: _inboxPageKey);
          break;
        case 1:
          _pages[index] = AccountPage(
            onNavigateToSaved: _navigateToSavedTab,
            onNavigateToInbox: _navigateToInboxTab,
            onTenantModeChanged: _handleTenantModeChanged,
          );
          break;
      }
      return;
    }

    switch (index) {
      case 0:
        _pages[index] = ExplorePage(
          key: _explorePageKey,
          onMarketplaceModeChanged: (active) =>
              setState(() => _isMarketplaceMode = active),
        );
        break;
      case 1:
        _pages[index] = SavedPage(key: _savedPageKey);
        break;
      case 2:
        _pages[index] = InboxPage(key: _inboxPageKey);
        break;
      case 3:
        _pages[index] = AccountPage(
          onNavigateToSaved: _navigateToSavedTab,
          onNavigateToInbox: _navigateToInboxTab,
          onTenantModeChanged: _handleTenantModeChanged,
        );
        break;
    }
  }

  void _navigateToSavedTab() {
    if (!AuthService.isTenantMode) {
      _navigateToTab(1, refreshSaved: true);
    }
  }

  void _navigateToInboxTab() {
    _navigateToTab(AuthService.isTenantMode ? 0 : 2);
  }

  void _handleTenantModeChanged(bool isTenant) {
    setState(() {
      _pages.fillRange(0, _pages.length, null);
      _tabHistory.clear();
      _tabHistory.add(0);
      _index = 0;
      _isMarketplaceMode = false;
      _ensurePageLoaded(0);
    });
  }

  void _navigateToTab(int index, {bool refreshSaved = false}) {
    setState(() {
      _index = index;
      if (_tabHistory.isEmpty || _tabHistory.last != index) {
        // Remove previous occurrence to avoid loops if needed, 
        // or just add to history stack
        _tabHistory.remove(index);
        _tabHistory.add(index);
      }
      _ensurePageLoaded(index);
    });

    if ((AuthService.isTenantMode && index == 0) || (!AuthService.isTenantMode && index == 2)) {
      unawaited(_refreshUnreadBadge());
    }

    if (!AuthService.isTenantMode && index == 1 && refreshSaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _savedPageKey.currentState?.refresh();
      });
    }
  }

  List<TelegramFragmentItem> _buildHomeTabs(int unreadInboxCount) {
    if (AuthService.isTenantMode) {
      return [
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_tabHistory.length > 1) {
          // Go back to previous tab
          setState(() {
            _tabHistory.removeLast();
            final previousIndex = _tabHistory.last;
            _index = previousIndex;
            _ensurePageLoaded(previousIndex);
          });
        } else {
          // We are at the root tab (Home/Inbox)
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            
            // Refresh the current tab
            if (_index == 0) {
              if (AuthService.isTenantMode) {
                _inboxPageKey.currentState?.refresh();
              } else {
                _explorePageKey.currentState?.refresh();
              }
            } else if (_index == 2 && !AuthService.isTenantMode) {
              _inboxPageKey.currentState?.refresh();
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // Double tap within 2 seconds
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _pointerDownPosition = event.position,
        onPointerUp: (event) {
          if (_pointerDownPosition != null && !_showBottomNav) {
            final distance = (event.position - _pointerDownPosition!).distance;
            if (distance < 10.0) {
              setState(() => _showBottomNav = true);
            }
          }
          _pointerDownPosition = null;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: IndexedStack(
            index: _index,
            children: List<Widget>.generate(
              _pages.length,
              (i) => _pages[i] ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _isMarketplaceMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GoogleAdBannerWidget(),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _showBottomNav
                      ? ValueListenableBuilder<int>(
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
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ),
      ),
    );
  }
}
