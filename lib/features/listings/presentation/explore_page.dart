import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:video_player/video_player.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/advertisement.dart';
import '../../../core/data/kenya_locations.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/dwelly_orbiting_loader.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/device_rental_cache_service.dart';
import '../../../core/services/client_identity_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/services/saved_rental_service.dart';
import '../../../core/services/user_preferences_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/google_ad_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/sqlite_cache_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/data_saver_service.dart';
import '../../../core/services/dwelly_media_cache_manager.dart';
import '../../helper/presentation/services_list_page.dart';
import '../../rentals/presentation/hashtag_search_page.dart';
import '../../../core/widgets/app_launch_ad_screen.dart';
import '../../../core/widgets/ad_break_screen.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/services/network_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'about_developer_page.dart';
import '../../../core/widgets/share_listing_sheet.dart';
import '../../../core/widgets/shimmer_placeholder.dart';
import '../../helper/presentation/helper_hub_page.dart';
import '../../../core/widgets/top_notification_bell.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import '../../lost_id/presentation/found_id_scan_page.dart';
import '../../lost_id/presentation/search_lost_id_page.dart';
import '../../rentals/domain/rental_filters.dart' show UnitType, UnitTypeLabel;

import 'rental_detail_page.dart';
import 'map_explore_page.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'premium_page.dart';
import 'package:realestate/features/user_profile/presentation/user_public_profile_page.dart';
import '../../../core/widgets/full_screen_image_avatar.dart';
import '../../../core/services/video_unlock_session_service.dart';
import '../../../core/services/feed_impression_service.dart';
import '../../../core/widgets/full_screen_gallery.dart';
import 'widgets/tiktok_rental_page.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => ExplorePageState();
}

class ExplorePageState extends State<ExplorePage> {
  // Rentals and pagination
  List<Rental> _rentals = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final Map<int, Future<void>> _activePrefetches = {};
  String? _error;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _usingLocationAwareFeed = false;
  bool _usingConstituencyFeed = false;
  static const int _pageSize = 10;
  static const int _loadMoreSize = 10;
  static const int _imagePrefetchCountFast = 6;
  static const int _imagePrefetchCountNormal = 4;
  static const int _imagePrefetchCountSlow = 2;

  // Search and filters
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _pageController = PageController();
  int _currentPageIndex = 0;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  String? _searchArea;
  List<String> _nearbyAreas = [];
  List<String> _borderNeighborAreas = [];
  String? _anchorWard;
  String? _anchorConstituency;
  String? _anchorCounty;
  bool _searchExhausted = false;
  String? _nextAction;
  bool _forceGlobalFeed = false;
  RentalFilters _filters = RentalFilters();
  bool _showFilters = false;

  // User preferences
  UserPreferencesService? _prefsService;
  bool _useFYP = false; // Feed mode: false = All, true = For You
  String? _feedViewerKey;

  // X-style feed impression tracking
  FeedImpressionService? _impressionService;
  Set<int> _clickedRentalIds = {};
  Map<int, int> _viewedTimestamps = {};
  final Map<int, Timer> _dwellTimers = {};
  int _newPropertiesAvailableCount = 0;
  bool _isRecycledFeed = false;

  // Ads
  AdService? _adService;
  List<int> _feedAdPositions = [];
  Map<int, Advertisement?> _feedAds = {}; // Position -> Ad
  Advertisement? _homeBannerAd;
  bool _showHelperBanner = true;
  Advertisement? _homeFeedAd;
  Advertisement? _searchResultsAd;
  Advertisement? _locationFilterAd;
  Advertisement? _interstitialAd;
  int _rentalTapCount = 0;

  // Memoization cache for _buildFeedItems to avoid O(N^2) list building on every frame while scrolling
  List<_ListItemInfo>? _cachedFeedItems;

  void _invalidateFeedCache() {
    _cachedFeedItems = null;
  }

  // Device location
  DeviceLocationResult? _deviceLocation;
  bool _isDetectingLocation = true;
  bool _hasAttemptedColdStartRetry = false;

  // Filter UI state
  final List<int> _bedroomOptions = [0, 1, 2, 3, 4, 5];
  int? _selectedBedrooms;
  double _minPrice = 0;
  double _maxPrice = 100000;
  RangeValues _priceRange = const RangeValues(0, 100000);

  // Property type filter
  UnitType? _selectedPropertyType;
  String? _selectedConstituency;

  // Scroll-aware header visibility
  bool _isHeaderVisible = true;
  bool _isServicesCompact = false;
  double _lastScrollOffset = 0;

  // Search autocomplete
  final _searchFocusNode = FocusNode();
  List<LocationSearchResult> _searchResults = [];
  Timer? _backendSearchDebounce;
  Timer? _scrollPrefetchDebounce;
  int _lastPrefetchAnchorIndex = -1;

  // Saved rental IDs (for bookmark state on cards)
  Set<int> _savedRentalIds = {};

  // Typewriter effect state
  Timer? _typewriterTimer;
  int _typewriterIndex = 0;
  String _typewriterText = '';
  final ValueNotifier<String> _typewriterNotifier = ValueNotifier<String>('');
  int _currentPlaceholderIndex = 0;
  bool _isTypingAnim = true;
  static const List<String> _placeholderTexts = [
    'Search "and filter by price"',
    'Search "lost id "',
    'Search "Kilimani"',
    'Search "South B"',
    'Search "Westlands"',
    'Search "Kileleshwa"',
    'Search "Lavington"',
    'Try "Near me"',
  ];

  bool get _hasSearchContext =>
      _searchArea != null && _searchArea!.trim().isNotEmpty;

  bool get _canShowHomeFeedAd => !_hasSearchContext && !_filters.hasFilters;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChange);
    ChatService.safetyVisibilityVersion.addListener(_onSafetyVisibilityChanged);
    NetworkService.instance.status.addListener(_onNetworkStatusChanged);
    _startTypewriterEffect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrapInitialState());
    });
  }

  Future<void> _bootstrapInitialState() async {
    await _initPreferences();
    unawaited(_loadSavedIds());
    unawaited(_loadHelperBannerState());
    unawaited(_tryDetectLocation());
  }

  @override
  void dispose() {
    for (final timer in _dwellTimers.values) {
      timer.cancel();
    }
    _dwellTimers.clear();
    _searchController.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    _backendSearchDebounce?.cancel();
    _scrollPrefetchDebounce?.cancel();
    _typewriterTimer?.cancel();
    _typewriterNotifier.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    ChatService.safetyVisibilityVersion.removeListener(
      _onSafetyVisibilityChanged,
    );
    NetworkService.instance.status.removeListener(_onNetworkStatusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// When network recovers and we're in an error state, auto-retry loading.
  void _onNetworkStatusChanged() {
    final status = NetworkService.instance.status.value;
    if ((status == NetworkStatus.online ||
            status == NetworkStatus.backOnline) &&
        _error != null &&
        !_isLoading &&
        mounted) {
      unawaited(_loadRentals(refresh: true));
    }
  }

  void _onSafetyVisibilityChanged() {
    if (!mounted) return;
    unawaited(_loadRentals(refresh: true));
  }

  Future<void> _initPreferences() async {
    final results = await Future.wait<dynamic>([
      UserPreferencesService.getInstance(),
      AdService.getInstance(),
      FeedImpressionService.getInstance(),
    ]);
    _prefsService = results[0] as UserPreferencesService;
    _adService = results[1] as AdService;
    _impressionService = results[2] as FeedImpressionService;
    _feedViewerKey = AuthService.currentUser?.id != null
        ? 'user:${AuthService.currentUser!.id}'
        : 'client:${await ClientIdentityService.getClientId()}';

    // Load clicked rental IDs and viewed timestamps for Fresh-First ranking
    final clickedIds = await _impressionService!.getClickedIds();
    final viewedTimestamps = await _impressionService!.getViewedTimestamps();
    if (mounted) {
      setState(() {
        _clickedRentalIds = clickedIds;
        _viewedTimestamps = viewedTimestamps;
      });
    }

    // Prune stale impression entries (older than 30 days)
    unawaited(_impressionService!.pruneOldEntries(30));

    // Sequence initial load through _tryDetectLocation after preferences and cache setup
    _loadHelperBannerState();
    unawaited(_tryDetectLocation());
  }

  Future<void> _loadHelperBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showHelperBanner = prefs.getBool('show_helper_banner_v1') ?? true;
    });
  }

  Future<void> _dismissHelperBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_helper_banner_v1', false);
    setState(() {
      _showHelperBanner = false;
    });
  }

  Future<void> _initAds() async {
    if (_adService == null) return;
    try {
      // Load feed ad positions
      final positions = await _adService!.getRentalFeedAdPositions();
      if (mounted) {
        setState(() => _feedAdPositions = positions);
      }

      await _refreshLocationAwareAds();
    } catch (e) {
      debugPrint('Failed to load ad config: $e');
    }
  }

  Future<void> _refreshLocationAwareAds() async {
    if (_adService == null) return;
    await Future.wait([_fetchPlacementAds(), _loadFeedAds()]);
  }

  Future<void> _fetchPlacementAds() async {
    if (_adService == null) return;
    final county = _deviceLocation?.county;
    final constituency = _deviceLocation?.constituency;

    try {
      final ads = await _adService!.getTargetedAdsBatch(
        [
          AdPlacement.HOME_BANNER,
          AdPlacement.HOME_FEED,
          AdPlacement.SEARCH_RESULTS,
          AdPlacement.LOCATION_FILTER,
          AdPlacement.INTERSTITIAL,
        ],
        county: county,
        constituency: constituency,
      );

      if (mounted) {
        setState(() {
          _invalidateFeedCache();
          _homeBannerAd = ads[AdPlacement.HOME_BANNER];
          _homeFeedAd = ads[AdPlacement.HOME_FEED];
          _searchResultsAd = ads[AdPlacement.SEARCH_RESULTS];
          _locationFilterAd = ads[AdPlacement.LOCATION_FILTER];
          _interstitialAd = ads[AdPlacement.INTERSTITIAL];
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch placement ads: $e');
    }
  }

  Future<void> _loadFeedAds() async {
    if (_adService == null) return;

    final nextFeedAds = <int, Advertisement?>{};

    Future<void> loadTargetedFallback() async {
      try {
        final targetedAd = await _adService!.getTargetedAd(
          AdPlacement.RENTAL_FEED,
          county: _deviceLocation?.county,
          constituency: _deviceLocation?.constituency,
        );
        if (targetedAd != null) {
          for (final position in _feedAdPositions) {
            nextFeedAds[position] = targetedAd;
          }
        }
      } catch (e) {
        debugPrint('Failed targeted feed ad fallback: $e');
      }
    }

    try {
      final feedAdPool = await _adService!.getAdsForPlacement(
        AdPlacement.RENTAL_FEED,
      );
      if (feedAdPool.isNotEmpty) {
        for (int i = 0; i < _feedAdPositions.length; i++) {
          final position = _feedAdPositions[i];
          nextFeedAds[position] = feedAdPool[i % feedAdPool.length];
        }
      } else {
        await loadTargetedFallback();
      }
    } catch (e) {
      debugPrint('Failed to load feed ad pool: $e');
      await loadTargetedFallback();
    }

    if (mounted) {
      setState(() {
        _invalidateFeedCache();
        _feedAds = nextFeedAds;
      });
    }
  }

  Future<void> _showLaunchAdIfNeeded() async {
    if (_adService == null) return;

    try {
      // Check if we should show launch ad (respects cooldown)
      final shouldShow = await _adService!.shouldShowLaunchAd();
      if (!shouldShow || !mounted) return;
      final config = await _adService!.getDisplayConfig();
      if (!mounted) return;

      if (!config.launchAdBreakEnabled) {
        final singleAd = await _adService!.getAppLaunchAd(
          county: _deviceLocation?.county,
          constituency: _deviceLocation?.constituency,
        );
        if (singleAd == null || !mounted) return;
        await Navigator.of(context).push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, _, __) => AppLaunchAdScreen(
              ad: singleAd,
              adService: _adService!,
              county: _deviceLocation?.county,
              constituency: _deviceLocation?.constituency,
              onComplete: () => Navigator.of(context).pop(),
            ),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
        return;
      }

      // Get launch break payload
      final breakPayload = await _adService!.getAppLaunchBreak(
        county: _deviceLocation?.county,
        constituency: _deviceLocation?.constituency,
      );

      if (breakPayload == null ||
          !breakPayload.available ||
          breakPayload.ads.isEmpty ||
          !mounted) {
        return;
      }

      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, _, __) => AdBreakScreen(
            ads: breakPayload.ads,
            adService: _adService!,
            firstAdUnskippable: config.launchAdFirstUnskippable,
            skipDelaySeconds: breakPayload.policy.skipDelaySeconds,
            breakId: breakPayload.breakId,
            placement: AdPlacement.APP_LAUNCH,
            county: _deviceLocation?.county,
            constituency: _deviceLocation?.constituency,
            markLaunchAdShownOnComplete: true,
            onComplete: () {
              Navigator.of(context).pop();
            },
          ),
          transitionsBuilder: (context, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('Failed to show launch ad: $e');
    }
  }

  Future<void> _showInterstitialIfDue() async {
    if (_adService == null || !mounted) return;

    _rentalTapCount++;
    if (_rentalTapCount % 4 != 0) return;
    final config = await _adService!.getDisplayConfig();

    final breakPayload = await _adService!.getAdBreak(
      AdPlacement.INTERSTITIAL,
      count: config.launchAdBreakCount.clamp(1, 2),
      county: _deviceLocation?.county,
      constituency: _deviceLocation?.constituency,
    );
    if (!mounted) return;

    final ads =
        config.launchAdBreakEnabled &&
            breakPayload != null &&
            breakPayload.ads.isNotEmpty
        ? breakPayload.ads
        : (_interstitialAd != null ? [_interstitialAd!] : <Advertisement>[]);
    if (ads.isEmpty) return;

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, _, __) => AdBreakScreen(
          ads: ads,
          adService: _adService!,
          placement: AdPlacement.INTERSTITIAL,
          firstAdUnskippable: config.launchAdFirstUnskippable,
          skipDelaySeconds: breakPayload?.policy.skipDelaySeconds ?? 5,
          breakId: breakPayload?.breakId,
          markLaunchAdShownOnComplete: false,
          county: _deviceLocation?.county,
          constituency: _deviceLocation?.constituency,
          onComplete: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _loadSavedIds() async {
    if (!AuthService.isLoggedIn) return;
    try {
      final ids = await SavedRentalService.getSavedRentalIds();
      if (mounted) setState(() => _savedRentalIds = ids.toSet());
    } catch (_) {}
  }

  void _startTypewriterEffect() {
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isHeaderVisible ||
          _searchController.text.isNotEmpty ||
          _isDetectingLocation ||
          _searchFocusNode.hasFocus)
        return;
      final currentText = _placeholderTexts[_currentPlaceholderIndex];
      if (_isTypingAnim) {
        if (_typewriterIndex < currentText.length) {
          _typewriterText = currentText.substring(0, _typewriterIndex + 1);
          _typewriterIndex++;
        } else {
          _isTypingAnim = false;
        }
      } else {
        if (_typewriterIndex > 0) {
          _typewriterIndex--;
          _typewriterText = currentText.substring(0, _typewriterIndex);
        } else {
          _isTypingAnim = true;
          _currentPlaceholderIndex =
              (_currentPlaceholderIndex + 1) % _placeholderTexts.length;
        }
      }
      _typewriterNotifier.value = _typewriterText;
    });
  }

  Future<void> _toggleSaveRental(int rentalId) async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to save listings'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Login',
            onPressed: () {
              showLoginBottomSheet(context, onSuccess: () => setState(() {}));
            },
          ),
        ),
      );
      return;
    }
    final wasSaved = _savedRentalIds.contains(rentalId);
    setState(() {
      if (wasSaved) {
        _savedRentalIds.remove(rentalId);
      } else {
        _savedRentalIds.add(rentalId);
      }
    });
    try {
      final success = wasSaved
          ? await SavedRentalService.unsaveRental(rentalId)
          : await SavedRentalService.saveRental(rentalId);
      if (!success && mounted) {
        setState(() {
          if (wasSaved) {
            _savedRentalIds.add(rentalId);
          } else {
            _savedRentalIds.remove(rentalId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${wasSaved ? 'unsave' : 'save'}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasSaved ? 'Removed from saved' : 'Added to saved'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (wasSaved) {
            _savedRentalIds.add(rentalId);
          } else {
            _savedRentalIds.remove(rentalId);
          }
        });
        showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Failed to update saved listing.',
        );
      }
    }
  }

  void _showReportDialog(Rental rental) {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to report a listing'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Login',
            onPressed: () {
              showLoginBottomSheet(context, onSuccess: () => setState(() {}));
            },
          ),
        ),
      );
      return;
    }
    if (rental.ownerId != null &&
        rental.ownerId == AuthService.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot report your own listing')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _ReportBottomSheet(rentalId: rental.id!, rentalTitle: rental.title),
    );
  }

  Future<void> _tryDetectLocation() async {
    bool rentalsLoaded = false;
    try {
      // 10-second deadline for location detection so first-launch OS permission prompt has enough time.
      await Future.any([
        _doDetectLocation().then((loaded) => rentalsLoaded = loaded),
        Future.delayed(const Duration(seconds: 10)),
      ]);
    } catch (_) {
      // Silently fail
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
        if (!rentalsLoaded) {
          unawaited(_loadRentals(refresh: false));
        }
      }
    }
  }

  /// Inner location detection logic, separated so _tryDetectLocation can
  /// enforce a hard timeout via Future.any.
  Future<bool> _doDetectLocation() async {
    // If we previously stored a denied flag, verify actual OS permission first.
    // Users may have re-enabled permission in system settings.
    final denied = await DeviceLocationService.hasUserDeniedLocation();
    if (denied) {
      final currentPermission = await DeviceLocationService.checkPermission();
      if (currentPermission == LocationPermission.always ||
          currentPermission == LocationPermission.whileInUse) {
        await DeviceLocationService.setUserDeniedLocation(false);
      } else if (currentPermission == LocationPermission.denied) {
        await DeviceLocationService.setUserDeniedLocation(false);
      } else if (currentPermission == LocationPermission.deniedForever) {
        return false;
      }
    }

    final result = await DeviceLocationService.getCurrentLocation(
      allowCachedFallback: true,
    );
    if (result.success && result.hasLocationData && mounted) {
      setState(() {
        _deviceLocation = result;
      });
      if (result.isOutsideKenya) {
        if (!_useFYP && !_hasSearchContext && !_filters.hasFilters) {
          setState(() {
            _invalidateFeedCache();
            _searchArea = result.displayName;
            _searchController.text = result.displayName;
            _rentals = [];
            _isLoading = false;
            _error = null;
            _hasMore = false;
          });
        }
        return false;
      }
      unawaited(_refreshLocationAwareAds());
    }
    return false;
  }

  void _onScroll() {
    final offset = _scrollController.position.pixels;
    if (offset > 40 && !_isServicesCompact) {
      setState(() => _isServicesCompact = true);
    }
    // Hide header on scroll up (finger moves up = offset increases)
    // Show header on scroll down (finger moves down = offset decreases)
    if ((offset - _lastScrollOffset).abs() > 5) {
      final scrollingDown =
          offset < _lastScrollOffset; // content moving down = user pulling down
      if (scrollingDown && !_isHeaderVisible) {
        setState(() => _isHeaderVisible = true);
      } else if (!scrollingDown && _isHeaderVisible && offset > 100) {
        setState(() => _isHeaderVisible = false);
      }
      _lastScrollOffset = offset;
    }
    // At top, always show header
    if (offset <= 0 && !_isHeaderVisible) {
      setState(() => _isHeaderVisible = true);
    }
    if (_scrollController.position.maxScrollExtent > 0 &&
        offset >= _scrollController.position.maxScrollExtent - 600) {
      _loadMoreRentals();
    }

    _scheduleViewportPrefetch();
  }

  void _scheduleViewportPrefetch() {
    if (_rentals.isEmpty || _isLoading || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;

    final estimatedIndex = (_scrollController.position.pixels / 540).floor();
    final anchorIndex = estimatedIndex.clamp(0, _rentals.length - 1);
    if ((anchorIndex - _lastPrefetchAnchorIndex).abs() < 2) return;

    _lastPrefetchAnchorIndex = anchorIndex;
    _scrollPrefetchDebounce?.cancel();
    _scrollPrefetchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_prefetchUpcomingRentals(anchorIndex));
    });
  }

  Future<void> _prefetchUpcomingRentals(int anchorIndex) async {
    if (!mounted || _rentals.isEmpty) return;

    final network = NetworkService.instance.status.value;
    if (network == NetworkStatus.offline) return;

    final windowSize = switch (network) {
      NetworkStatus.backOnline => 8,
      NetworkStatus.online => 6,
      NetworkStatus.slow => 2,
      NetworkStatus.offline => 0,
    };
    if (windowSize <= 0) return;

    final start = (anchorIndex + 1).clamp(0, _rentals.length);
    final end = (start + windowSize).clamp(0, _rentals.length);
    if (start >= end) return;

    await _prefetchRentalCardThumbnails(_rentals.sublist(start, end));
  }

  /// Get FYP preferred areas — user's fypWards/fypNicknames first, then local prefs
  List<String> _getFypPreferredAreas() {
    final user = AuthService.currentUser;
    if (user != null && user.hasFypPreferences) {
      return [...user.fypWards, ...user.fypNicknames];
    }
    return _prefsService?.getPreferredAreas() ?? [];
  }

  bool _isListingUnseen(Rental rental) {
    if (rental.id == null) return true;
    final lastViewed = _viewedTimestamps[rental.id!];
    if (lastViewed == null) {
      if (_clickedRentalIds.contains(rental.id)) {
        return false;
      }
      return true;
    }
    if (rental.updatedAt != null) {
      if (rental.updatedAt!.millisecondsSinceEpoch > lastViewed) {
        return true;
      }
    }
    return false;
  }

  bool _isEffectivelySponsored(Rental rental) {
    if (rental.sponsorshipType == null || rental.sponsorshipType == 'NONE') return false;
    if (rental.sponsorshipType == 'BOTH') return true;
    if (_usingLocationAwareFeed && rental.sponsorshipType == 'LOCAL') return true;
    if (!_usingLocationAwareFeed && rental.sponsorshipType == 'SEARCH') return true;
    return false;
  }

  void _enforceSponsoredOnTop() {
    _invalidateFeedCache();
    if (_rentals.isEmpty) return;
    final sponsored = _rentals.where((r) => _isEffectivelySponsored(r)).toList();
    final unseen = _rentals
        .where((r) => !_isEffectivelySponsored(r) && _isListingUnseen(r))
        .toList();
    final viewed = _rentals
        .where((r) => !_isEffectivelySponsored(r) && !_isListingUnseen(r))
        .toList();
    _rentals.clear();
    _rentals.addAll(sponsored);
    _rentals.addAll(unseen);
    _rentals.addAll(viewed);
  }

  Future<void> refresh() async {
    // If not at top, jump to top first
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    
    // Show the visual loading animation, which automatically calls onRefresh!
    _refreshIndicatorKey.currentState?.show();
  }

  Future<void> _loadRentals({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _invalidateFeedCache();
        _isServicesCompact = false;
        _currentPage = 0;
        _hasMore = true;
        _rentals.clear();
        _isRecycledFeed = false;
      });
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final isColdStart = _currentPage == 0 && _rentals.isEmpty;
      final timeoutDuration = isColdStart
          ? const Duration(seconds: 15)
          : const Duration(seconds: 8);
      final result = await _fetchRentals(
        refresh: refresh,
      ).timeout(timeoutDuration);

      if (!mounted) return;

      // Refresh clicked IDs and viewed timestamps FIRST (needed for Fresh-First filtering)
      if (_impressionService != null) {
        final clickedIds = await _impressionService!.getClickedIds();
        final viewedTimestamps = await _impressionService!
            .getViewedTimestamps();
        _clickedRentalIds = clickedIds;
        _viewedTimestamps = viewedTimestamps;
      }

      // Fresh-First TikTok-Style: hide viewed listings from primary feed
      List<Rental> filteredRentals = result.rentals;
      if (!_isRecycledFeed) {
        final unseenRentals = filteredRentals
            .where((r) => _isEffectivelySponsored(r) || _isListingUnseen(r))
            .toList();

        if (unseenRentals.where((r) => !_isEffectivelySponsored(r)).isEmpty &&
            !result.hasMore) {
          // ALL listings are viewed and no more pages — show revisit feed
          debugPrint(
            '[FreshFirst] All listings viewed, switching to revisit feed',
          );
          if (mounted) {
            setState(() => _isRecycledFeed = true);
          }
          // Keep all listings but show the revisit banner
        } else if (unseenRentals.where((r) => !_isEffectivelySponsored(r)).isEmpty &&
            result.hasMore) {
          // This page had all viewed listings but there are more pages — skip to next
          debugPrint('[FreshFirst] Page fully viewed, loading more...');
          setState(() {
            _invalidateFeedCache();
            _rentals = unseenRentals; // just sponsored for now
            _currentPage = 0;
            _isLoading = false;
            _hasMore = true;
          });
          return _loadMoreRentals();
        } else {
          // There are unseen listings — show only those (plus sponsored)
          filteredRentals = unseenRentals;
        }
      }

      setState(() {
        _invalidateFeedCache();
        _rentals = filteredRentals;
        _enforceSponsoredOnTop();
        _hasMore = result.hasMore;
        _currentPage = 0;
        _isLoading = false;
      });
      unawaited(_prefetchRentalCardThumbnails(filteredRentals));
      if (result.hasMore) {
        _prefetchPageInBackground(1);
        if (result.totalPages > 2) {
          _prefetchPageInBackground(2);
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (_rentals.isEmpty &&
          _currentPage == 0 &&
          !_hasAttemptedColdStartRetry) {
        _hasAttemptedColdStartRetry = true;
        debugPrint('Cold start load failed ($e), retrying silently in 1.5s...');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          return _loadRentals(refresh: refresh);
        }
      }
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load rentals.',
        );
        _isLoading = false;
      });
    }
  }

  /// Inner fetch logic extracted so _loadRentals can enforce a hard timeout.
  Future<PaginatedRentals> _fetchRentals({bool refresh = false}) async {
    final hasConstituencyFilter =
        _filters.constituency != null && _filters.constituency!.isNotEmpty;
    _nearbyAreas = [];
    _borderNeighborAreas = [];
    _anchorWard = null;
    _anchorConstituency = null;
    _anchorCounty = null;
    _searchExhausted = false;
    _nextAction = null;

    if (_deviceLocation != null &&
        _deviceLocation!.isOutsideKenya &&
        (_searchArea == null ||
            _searchArea!.isEmpty ||
            _searchArea == _deviceLocation!.displayName ||
            _searchArea == _deviceLocation!.areaName ||
            _searchArea == _deviceLocation!.detailedDisplayName)) {
      // Silently don't request for listings when location is outside Kenya
      return PaginatedRentals(
        rentals: [],
        totalElements: 0,
        totalPages: 0,
        currentPage: 0,
        hasMore: false,
      );
    }

    final isDeviceLocationSearch = _deviceLocation != null &&
        _searchArea != null &&
        (_searchArea == _deviceLocation!.displayName ||
            _searchArea == _deviceLocation!.areaName ||
            _searchArea == _deviceLocation!.detailedDisplayName);

    if (_searchArea != null && _searchArea!.isNotEmpty && !isDeviceLocationSearch) {
      // Use backend smart location search with filters
      final searchResult = await RentalService.smartLocationSearch(
        nickname: _searchArea,
        constituency: _filters.constituency,
        county: _filters.county,
        strictConstituency: hasConstituencyFilter,
        includeNearby: true,
        minPrice: _filters.minPrice,
        maxPrice: _filters.maxPrice,
        propertyType: _filters.propertyType,
        bedrooms: _filters.bedrooms,
        page: 0,
        size: _pageSize,
        forceNetwork: refresh,
      );
      _nearbyAreas = searchResult.nearbyAreas;
      _borderNeighborAreas = searchResult.borderNeighborAreas;
      _anchorWard = searchResult.anchorWard ?? searchResult.resolvedWard;
      _anchorConstituency =
          searchResult.anchorConstituency ?? searchResult.resolvedConstituency;
      _anchorCounty = searchResult.anchorCounty ?? searchResult.resolvedCounty;
      _searchExhausted = searchResult.searchExhausted;
      _nextAction = searchResult.nextAction;
      _usingLocationAwareFeed = false;
      _usingConstituencyFeed = false;
      return searchResult.rentals;
    } else if (_useFYP) {
      // FYP recommendations using user's fypWards/fypNicknames or local prefs
      final preferredAreas = _getFypPreferredAreas();
      final expandedBedrooms =
          _prefsService?.getExpandedBedroomPreferences() ?? [];
      final priceRange = _prefsService?.getPreferredPriceRange();

      final result = await RentalService.getRecommendations(
        page: 0,
        size: _pageSize,
        preferredAreas: preferredAreas.isNotEmpty ? preferredAreas : null,
        expandedBedrooms: expandedBedrooms.isNotEmpty ? expandedBedrooms : null,
        minPrice: _filters.minPrice ?? priceRange?.min,
        maxPrice: _filters.maxPrice ?? priceRange?.max,
      );
      _usingLocationAwareFeed = false;
      _usingConstituencyFeed = false;
      return result;
    } else if (hasConstituencyFilter) {
      final searchResult = await RentalService.smartLocationSearch(
        constituency: _filters.constituency,
        strictConstituency: true,
        includeNearby: true,
        minPrice: _filters.minPrice,
        maxPrice: _filters.maxPrice,
        propertyType: _filters.propertyType,
        bedrooms: _filters.bedrooms,
        page: 0,
        size: _pageSize,
        forceNetwork: refresh,
      );
      _nearbyAreas = searchResult.nearbyAreas;
      _borderNeighborAreas = searchResult.borderNeighborAreas;
      _anchorWard = searchResult.anchorWard ?? searchResult.resolvedWard;
      _anchorConstituency =
          searchResult.anchorConstituency ?? searchResult.resolvedConstituency;
      _anchorCounty = searchResult.anchorCounty ?? searchResult.resolvedCounty;
      _searchExhausted = searchResult.searchExhausted;
      _nextAction = searchResult.nextAction;
      _usingLocationAwareFeed = false;
      _usingConstituencyFeed = true;
      return searchResult.rentals;
    } else if (_forceGlobalFeed) {
      final result = await RentalService.getPaginated(
        page: 0,
        size: _pageSize,
        filters: _filters,
        forceNetwork: refresh,
      );
      _usingLocationAwareFeed = false;
      _usingConstituencyFeed = false;
      _forceGlobalFeed = false;
      return result;
    } else if (_deviceLocation != null && _deviceLocation!.hasLocationData) {
      // Default feed is location-first: user's ward first, then constituency neighbors.
      try {
        final searchResult = await RentalService.smartLocationSearch(
          ward: hasConstituencyFilter ? null : _deviceLocation!.ward,
          constituency: hasConstituencyFilter
              ? _filters.constituency
              : _deviceLocation!.constituency,
          strictConstituency: hasConstituencyFilter,
          county: _deviceLocation!.county,
          latitude: _deviceLocation!.latitude,
          longitude: _deviceLocation!.longitude,
          sortByDistance: true,
          includeNearby: true,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          propertyType: _filters.propertyType,
          bedrooms: _filters.bedrooms,
          page: 0,
          size: _pageSize,
          forceNetwork: refresh,
        );

        _nearbyAreas = searchResult.nearbyAreas;
        _borderNeighborAreas = searchResult.borderNeighborAreas;
        _anchorWard = searchResult.anchorWard ?? searchResult.resolvedWard;
        _anchorConstituency =
            searchResult.anchorConstituency ??
            searchResult.resolvedConstituency;
        _anchorCounty =
            searchResult.anchorCounty ?? searchResult.resolvedCounty;
        _searchExhausted = searchResult.searchExhausted;
        _nextAction = searchResult.nextAction;
        if (searchResult.rentals.rentals.isNotEmpty ||
            searchResult.rentals.totalElements > 0) {
          _usingLocationAwareFeed = true;
          _usingConstituencyFeed = false;
          return searchResult.rentals;
        } else {
          _usingLocationAwareFeed = false;
          _usingConstituencyFeed = false;
          return await RentalService.getPaginated(
            page: 0,
            size: _pageSize,
            filters: _filters,
            forceNetwork: refresh,
          );
        }
      } catch (_) {
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = false;
        return await RentalService.getPaginated(
          page: 0,
          size: _pageSize,
          filters: _filters,
          forceNetwork: refresh,
        );
      }
    } else {
      // Regular paginated load with filters
      _usingLocationAwareFeed = false;
      _usingConstituencyFeed = false;
      return await RentalService.getPaginated(
        page: 0,
        size: _pageSize,
        filters: _filters,
        forceNetwork: refresh,
      );
    }
  }

  Future<void> _loadMoreRentals() async {
    if (_isLoadingMore) return;
    if (!_hasMore) {
      if (!_isRecycledFeed) {
        debugPrint(
          '[Feed Recycle] Reached end of fresh listings! Switching to revisit feed...',
        );
        if (mounted) {
          setState(() => _isRecycledFeed = true);
          return _loadRentals(refresh: false);
        }
      }
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final signature = SqliteCacheService.generateSignature(
        _filters,
        _loadMoreSize,
        viewerKey: _feedViewerKey,
      );

      // Check if this exact page is already pre-cached in SQLite
      var localData = await SqliteCacheService.instance.getPaginatedFeed(
        signature,
        nextPage,
      );

      // If NOT in SQLite yet, but a background prefetch is actively running for this page right now, wait for it!
      if (localData == null && _activePrefetches.containsKey(nextPage)) {
        debugPrint(
          '[Prefetch Lock] Fast scroll detected! Waiting for active background prefetch of page $nextPage...',
        );
        try {
          await _activePrefetches[nextPage]!.timeout(
            const Duration(seconds: 12),
          );
        } catch (_) {}
        // Re-check SQLite after waiting for the active prefetch to complete
        localData = await SqliteCacheService.instance.getPaginatedFeed(
          signature,
          nextPage,
        );
      }

      if (localData != null && localData.rentals.isNotEmpty) {
        debugPrint(
          '[Prefetch Lock] Instant cache hit for page $nextPage after fast scroll!',
        );
        if (!mounted) return;

        // Fresh-First: filter out viewed listings from cached data
        List<Rental> cachedRentals = localData.rentals;
        if (!_isRecycledFeed) {
          cachedRentals = cachedRentals
              .where((r) => _isEffectivelySponsored(r) || _isListingUnseen(r))
              .toList();
        }

        final existingIds = _rentals.map((r) => r.id).toSet();
        final newRentals = cachedRentals
            .where((r) => !existingIds.contains(r.id))
            .toList();

        // If all cached listings were viewed and no more pages, switch to revisit feed
        if (newRentals.isEmpty && !localData.hasMore && !_isRecycledFeed) {
          setState(() {
            _isRecycledFeed = true;
            _isLoadingMore = false;
          });
          return _loadRentals(refresh: false);
        }

        setState(() {
          _invalidateFeedCache();
          _rentals.addAll(newRentals);
          _enforceSponsoredOnTop();
          if (newRentals.isEmpty) {
            _hasMore = false;
          } else {
            _hasMore = localData!.hasMore;
          }
          _currentPage = nextPage;
          _isLoadingMore = false;
        });
        unawaited(_prefetchRentalCardThumbnails(localData!.rentals));
        if (localData.hasMore) {
          _prefetchPageInBackground(nextPage + 1);
          if (localData.totalPages > nextPage + 2) {
            _prefetchPageInBackground(nextPage + 2);
          }
        }
        return;
      }

      PaginatedRentals result;
      final hasConstituencyFilter =
          _filters.constituency != null && _filters.constituency!.isNotEmpty;

      if (_searchArea != null && _searchArea!.isNotEmpty) {
        try {
          final searchResult = await RentalService.smartLocationSearch(
            nickname: _searchArea,
            constituency: _filters.constituency,
            strictConstituency: hasConstituencyFilter,
            includeNearby: true,
            minPrice: _filters.minPrice,
            maxPrice: _filters.maxPrice,
            propertyType: _filters.propertyType,
            bedrooms: _filters.bedrooms,
            page: nextPage,
            size: _loadMoreSize,
          ).timeout(const Duration(seconds: 15));
          _searchExhausted = searchResult.searchExhausted;
          _nextAction = searchResult.nextAction;
          result = searchResult.rentals;
        } catch (_) {
          result = await RentalService.getPaginated(
            page: nextPage,
            size: _loadMoreSize,
            filters: _filters,
          ).timeout(const Duration(seconds: 10));
        }
      } else if (_usingConstituencyFeed && hasConstituencyFilter) {
        try {
          final searchResult = await RentalService.smartLocationSearch(
            constituency: _filters.constituency,
            strictConstituency: true,
            includeNearby: true,
            minPrice: _filters.minPrice,
            maxPrice: _filters.maxPrice,
            propertyType: _filters.propertyType,
            bedrooms: _filters.bedrooms,
            page: nextPage,
            size: _loadMoreSize,
          ).timeout(const Duration(seconds: 15));
          _searchExhausted = searchResult.searchExhausted;
          _nextAction = searchResult.nextAction;
          result = searchResult.rentals;
        } catch (_) {
          result = await RentalService.getPaginated(
            page: nextPage,
            size: _loadMoreSize,
            filters: _filters,
          ).timeout(const Duration(seconds: 10));
        }
      } else if (_useFYP) {
        final preferredAreas = _getFypPreferredAreas();
        final expandedBedrooms =
            _prefsService?.getExpandedBedroomPreferences() ?? [];
        final priceRange = _prefsService?.getPreferredPriceRange();

        result = await RentalService.getRecommendations(
          page: nextPage,
          size: _loadMoreSize,
          preferredAreas: preferredAreas.isNotEmpty ? preferredAreas : null,
          expandedBedrooms: expandedBedrooms.isNotEmpty
              ? expandedBedrooms
              : null,
          minPrice: _filters.minPrice ?? priceRange?.min,
          maxPrice: _filters.maxPrice ?? priceRange?.max,
        ).timeout(const Duration(seconds: 15));
      } else if (_usingLocationAwareFeed &&
          _deviceLocation != null &&
          _deviceLocation!.hasLocationData) {
        try {
          final searchResult = await RentalService.smartLocationSearch(
            ward: hasConstituencyFilter ? null : _deviceLocation!.ward,
            constituency: hasConstituencyFilter
                ? _filters.constituency
                : _deviceLocation!.constituency,
            strictConstituency: hasConstituencyFilter,
            county: _deviceLocation!.county,
            latitude: _deviceLocation!.latitude,
            longitude: _deviceLocation!.longitude,
            sortByDistance: true,
            includeNearby: true,
            minPrice: _filters.minPrice,
            maxPrice: _filters.maxPrice,
            propertyType: _filters.propertyType,
            bedrooms: _filters.bedrooms,
            page: nextPage,
            size: _loadMoreSize,
          ).timeout(const Duration(seconds: 15));
          _searchExhausted = searchResult.searchExhausted;
          _nextAction = searchResult.nextAction;
          result = searchResult.rentals;
        } catch (_) {
          result = await RentalService.getPaginated(
            page: nextPage,
            size: _loadMoreSize,
            filters: _filters,
          ).timeout(const Duration(seconds: 10));
        }
      } else {
        result = await RentalService.getPaginated(
          page: nextPage,
          size: _loadMoreSize,
          filters: _filters,
        ).timeout(const Duration(seconds: 15));
      }

      if (!mounted) return;

      // Fresh-First: filter out viewed listings from network/fallback data
      List<Rental> newRentals = result.rentals;
      if (!_isRecycledFeed) {
        newRentals = newRentals
            .where((r) => _isEffectivelySponsored(r) || _isListingUnseen(r))
            .toList();
      }

      // Deduplicate against already-shown listings
      final existingIds = _rentals.map((r) => r.id).toSet();
      newRentals = newRentals
          .where((r) => !existingIds.contains(r.id))
          .toList();

      // If all new listings were viewed/dupes and no more pages, switch to revisit feed
      if (newRentals.isEmpty && !result.hasMore && !_isRecycledFeed) {
        if (mounted) {
          setState(() {
            _isRecycledFeed = true;
            _isLoadingMore = false;
          });
          return _loadRentals(refresh: false);
        }
        return;
      }

      setState(() {
        _invalidateFeedCache();
        _rentals.addAll(newRentals);
        _enforceSponsoredOnTop();
        if (newRentals.isEmpty) {
          _hasMore = false;
        } else {
          _hasMore = result.hasMore;
        }
        _currentPage = nextPage;
        _isLoadingMore = false;
      });
      unawaited(_prefetchRentalCardThumbnails(result.rentals));
      if (_hasMore) {
        _prefetchPageInBackground(nextPage + 1);
        if (result.totalPages > nextPage + 2) {
          _prefetchPageInBackground(nextPage + 2);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      debugPrint('Failed to load more rentals: $e');
    }
  }

  /// Silently pre-fetches [targetPage] into SQLite in the background so scrolling to the next 10 items
  /// happens instantly without lag. Also prunes older pages to strictly maintain the
  /// [previous 10, current 10, next 10] sliding window in persistent storage.
  Future<void> _prefetchPageInBackground(int targetPage) async {
    if (!_hasMore || _searchExhausted || _isLoadingMore || _isLoading) return;
    if (_activePrefetches.containsKey(targetPage)) return;

    final prefetchFuture = _doPrefetchPage(targetPage);
    _activePrefetches[targetPage] = prefetchFuture;
    try {
      await prefetchFuture;
    } finally {
      _activePrefetches.remove(targetPage);
    }
  }

  Future<void> _doPrefetchPage(int targetPage) async {
    try {
      final hasConstituencyFilter =
          _filters.constituency != null && _filters.constituency!.isNotEmpty;
      final signature = SqliteCacheService.generateSignature(
        _filters,
        _loadMoreSize,
        viewerKey: _feedViewerKey,
      );

      // Prune SQLite cache to strictly keep [currentPage - 3 to currentPage + 3] (70 items total)
      await SqliteCacheService.instance.pruneFeedCache(
        signature,
        _currentPage,
        window: 3,
      );

      // Check if already in cache
      final existing = await SqliteCacheService.instance.getPaginatedFeed(
        signature,
        targetPage,
      );
      if (existing != null && existing.rentals.isNotEmpty) {
        return;
      }

      if (_searchArea != null && _searchArea!.isNotEmpty) {
        await RentalService.smartLocationSearch(
          nickname: _searchArea,
          constituency: _filters.constituency,
          strictConstituency: hasConstituencyFilter,
          includeNearby: true,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          propertyType: _filters.propertyType,
          bedrooms: _filters.bedrooms,
          page: targetPage,
          size: _loadMoreSize,
        ).timeout(const Duration(seconds: 15));
      } else if (_usingConstituencyFeed && hasConstituencyFilter) {
        await RentalService.smartLocationSearch(
          constituency: _filters.constituency,
          strictConstituency: true,
          includeNearby: true,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          propertyType: _filters.propertyType,
          bedrooms: _filters.bedrooms,
          page: targetPage,
          size: _loadMoreSize,
        ).timeout(const Duration(seconds: 15));
      } else if (_useFYP) {
        final preferredAreas = _getFypPreferredAreas();
        final expandedBedrooms =
            _prefsService?.getExpandedBedroomPreferences() ?? [];
        final priceRange = _prefsService?.getPreferredPriceRange();

        await RentalService.getRecommendations(
          page: targetPage,
          size: _loadMoreSize,
          preferredAreas: preferredAreas.isNotEmpty ? preferredAreas : null,
          expandedBedrooms: expandedBedrooms.isNotEmpty
              ? expandedBedrooms
              : null,
          minPrice: _filters.minPrice ?? priceRange?.min,
          maxPrice: _filters.maxPrice ?? priceRange?.max,
        ).timeout(const Duration(seconds: 15));
      } else if (_usingLocationAwareFeed &&
          _deviceLocation != null &&
          _deviceLocation!.hasLocationData) {
        await RentalService.smartLocationSearch(
          ward: hasConstituencyFilter ? null : _deviceLocation!.ward,
          constituency: hasConstituencyFilter
              ? _filters.constituency
              : _deviceLocation!.constituency,
          strictConstituency: hasConstituencyFilter,
          county: _deviceLocation!.county,
          latitude: _deviceLocation!.latitude,
          longitude: _deviceLocation!.longitude,
          sortByDistance: true,
          includeNearby: true,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          propertyType: _filters.propertyType,
          bedrooms: _filters.bedrooms,
          page: targetPage,
          size: _loadMoreSize,
        ).timeout(const Duration(seconds: 15));
      } else {
        await RentalService.getPaginated(
          page: targetPage,
          size: _loadMoreSize,
          filters: _filters,
        ).timeout(const Duration(seconds: 15));
      }

      // Precache/pre-warm thumbnails for the prefetched next items so cards pop in instantly.
      final prefetched = await SqliteCacheService.instance.getPaginatedFeed(
        signature,
        targetPage,
      );
      if (prefetched != null) {
        await _prefetchRentalCardThumbnails(prefetched.rentals);
      }
    } catch (e) {
      debugPrint(
        '[Prefetch] Background prefetch for page $targetPage skipped safely: $e',
      );
    }
  }

  Future<void> _prefetchRentalCardThumbnails(List<Rental> rentals) async {
    if (!mounted) return;
    
    for (final rental in rentals) {
      if (!mounted) break;
      
      final urlsToPrefetch = <String>[];
      
      if (rental.hasVideo && rental.cardDisplayPreference == 'VIDEO') {
        if (rental.videoUrl != null) {
          urlsToPrefetch.add(ApiService.getFeedThumbnailUrl(rental.videoUrl));
        } else if (rental.compoundVideoUrl != null) {
          urlsToPrefetch.add(ApiService.getFeedThumbnailUrl(rental.compoundVideoUrl));
        }
      } else if (rental.cardDisplayPreference == 'THREE_PICTURES') {
        for (int i = 0; i < 3; i++) {
          if (i < rental.thumbnailUrls.length) {
            urlsToPrefetch.add(rental.thumbnailUrls[i]);
          } else if (i < rental.imageUrls.length) {
            urlsToPrefetch.add(ApiService.getFeedThumbnailUrl(rental.imageUrls[i]));
          }
        }
      } else if (rental.cardDisplayPreference == 'DOUBLE_PICTURE') {
        for (int i = 0; i < 2; i++) {
          if (i < rental.thumbnailUrls.length) {
            urlsToPrefetch.add(rental.thumbnailUrls[i]);
          } else if (i < rental.imageUrls.length) {
            urlsToPrefetch.add(ApiService.getFeedThumbnailUrl(rental.imageUrls[i]));
          }
        }
      } else {
        // Default: just 1 picture
        if (rental.thumbnailUrls.isNotEmpty) {
          urlsToPrefetch.add(rental.thumbnailUrls.first);
        } else if (rental.imageUrls.isNotEmpty) {
          urlsToPrefetch.add(ApiService.getFeedThumbnailUrl(rental.imageUrls.first));
        }
      }

      for (final targetUrl in urlsToPrefetch) {
        if (targetUrl.isNotEmpty) {
          try {
            precacheImage(CachedNetworkImageProvider(targetUrl), context);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _onSearch(String query) async {
    _prefsService?.recordSearch(query);

    setState(() {
      _searchArea = query.isNotEmpty ? query : null;
      _forceGlobalFeed = false;
      if (query.isNotEmpty) {
        _useFYP = false;
      }
    });

    await _loadRentals(refresh: true);
  }

  String? _activeAnchorLabel() {
    if (_anchorWard != null && _anchorWard!.trim().isNotEmpty) {
      return _anchorWard;
    }
    if (_anchorConstituency != null && _anchorConstituency!.trim().isNotEmpty) {
      return _anchorConstituency;
    }
    if (_anchorCounty != null && _anchorCounty!.trim().isNotEmpty) {
      return _anchorCounty;
    }
    return _searchArea;
  }

  Future<void> _broadenToConstituency() async {
    final constituency = _anchorConstituency;
    if (constituency == null || constituency.isEmpty) return;
    setState(() {
      _selectedConstituency = constituency;
      _searchArea = null;
      _filters = _replaceLocationFilters(
        area: null,
        constituency: constituency,
      );
      _forceGlobalFeed = false;
    });
    await _loadRentals(refresh: true);
  }

  Future<void> _broadenToCounty() async {
    final county = _anchorCounty;
    if (county == null || county.isEmpty) return;
    setState(() {
      _searchArea = county;
      _selectedConstituency = null;
      _filters = _replaceLocationFilters(area: county, constituency: null);
      _forceGlobalFeed = false;
    });
    _searchController.text = county;
    await _loadRentals(refresh: true);
  }

  Future<void> _showAllKenya() async {
    setState(() {
      _searchArea = null;
      _selectedConstituency = null;
      _filters = _replaceLocationFilters(area: null, constituency: null);
      _forceGlobalFeed = true;
    });
    _searchController.clear();
    await _loadRentals(refresh: true);
  }

  RentalFilters _replaceLocationFilters({
    required String? area,
    required String? constituency,
    String? county,
  }) {
    return RentalFilters(
      area: area,
      constituency: constituency,
      county: county ?? _filters.county,
      nearbyAreas: _filters.nearbyAreas,
      minPrice: _filters.minPrice,
      maxPrice: _filters.maxPrice,
      bedrooms: _filters.bedrooms,
      bathrooms: _filters.bathrooms,
      propertyType: _filters.propertyType,
      expandedBedrooms: _filters.expandedBedrooms,
    );
  }

  void _applyFilters() {
    setState(() {
      _filters = RentalFilters(
        area: _searchArea,
        constituency: _selectedConstituency,
        county: _filters.county,
        minPrice: _priceRange.start > 0 ? _priceRange.start : null,
        maxPrice: _priceRange.end < _maxPrice ? _priceRange.end : null,
        bedrooms: _selectedBedrooms,
        propertyType: _selectedPropertyType?.backendName,
      );
      _showFilters = false;
      _forceGlobalFeed = false;
    });
    _loadRentals(refresh: true);
  }

  void _clearFilters() {
    setState(() {
      _selectedBedrooms = null;
      _selectedPropertyType = null;
      _selectedConstituency = null;
      _priceRange = RangeValues(_minPrice, _maxPrice);
      _filters = RentalFilters(
        area: _searchArea,
        constituency: _filters.constituency,
        county: _filters.county,
      );
      _showFilters = false;
    });
    _loadRentals(refresh: true);
  }

  // ==================== Search Autocomplete ====================

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) {
      // Select all pre-filled text so user can type fresh
      if (_searchController.text.isNotEmpty) {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      }
    } else {
      // Clear suggestions when losing focus (delay lets taps register)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_searchFocusNode.hasFocus) {
          setState(() => _searchResults = []);
        }
      });
    }
    if (mounted) setState(() {});
  }

  void _onSearchTextChanged(String query) {
    // Update clear button visibility
    setState(() {});

    if (query.isEmpty) {
      setState(() => _searchResults = []);
      _backendSearchDebounce?.cancel();
      return;
    }

    // Instant local search (static wards/constituencies/areas)
    setState(() {
      _searchResults = KenyaLocations.searchLocations(query);
    });

    // Debounced backend search for dynamic nicknames
    _backendSearchDebounce?.cancel();
    _backendSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        final backendResults = await RentalService.searchAreas(query);
        if (!mounted || _searchController.text != query) return;

        final existingNames = _searchResults
            .map((r) => r.name.toLowerCase())
            .toSet();
        final newResults = <LocationSearchResult>[];

        for (final br in backendResults) {
          if (!existingNames.contains(br.name.toLowerCase())) {
            newResults.add(br);
            existingNames.add(br.name.toLowerCase());
          } else if (br.listingCount > 0) {
            _searchResults = _searchResults.map((r) {
              if (r.name.toLowerCase() == br.name.toLowerCase()) {
                return LocationSearchResult(
                  name: r.name,
                  type: r.type,
                  county: br.county ?? r.county,
                  constituency: br.constituency ?? r.constituency,
                  ward: br.ward ?? r.ward,
                  listingCount: br.listingCount,
                );
              }
              return r;
            }).toList();
          }
        }

        _searchResults = [..._searchResults, ...newResults];
        _searchResults.sort((a, b) {
          if (a.listingCount != b.listingCount) {
            return b.listingCount.compareTo(a.listingCount);
          }
          return a.type.index.compareTo(b.type.index);
        });

        if (_searchResults.length > 20) {
          _searchResults = _searchResults.sublist(0, 20);
        }

        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  void _onSuggestionSelected(LocationSearchResult result) {
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
      _searchController.text = result.name;
      _searchArea = result.name;
      String? selectedCounty = result.county;
      if (result.type == LocationType.constituency) {
        _selectedConstituency = result.name;
      } else if (result.type == LocationType.ward &&
          result.constituency != null) {
        _selectedConstituency = result.constituency;
      }
      _filters = _filters.copyWith(
        constituency: _selectedConstituency,
        county: selectedCounty,
      );
      _useFYP = false;
    });
    _loadRentals(refresh: true);
  }

  IconData _getTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Icons.location_city;
      case LocationType.constituency:
        return Icons.pin_drop;
      case LocationType.ward:
        return Icons.holiday_village;
      case LocationType.area:
        return Icons.star;
    }
  }

  Color _getTypeColor(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Colors.blue;
      case LocationType.constituency:
        return Colors.green;
      case LocationType.ward:
        return Colors.purple;
      case LocationType.area:
        return Colors.amber;
    }
  }

  String _getTypeLabel(LocationType type) {
    switch (type) {
      case LocationType.county:
        return 'County';
      case LocationType.constituency:
        return 'Constituency';
      case LocationType.ward:
        return 'Ward';
      case LocationType.area:
        return 'Area';
    }
  }

  IconData _getUnitTypeIcon(UnitType type) {
    switch (type) {
      case UnitType.bedsitter:
        return Icons.single_bed;
      case UnitType.singleRoom:
        return Icons.bed;
      case UnitType.doubleRoom:
        return Icons.king_bed;
      case UnitType.room:
        return Icons.door_back_door_outlined;
      case UnitType.studio:
        return Icons.weekend;
      case UnitType.airBnB:
        return Icons.travel_explore;
      case UnitType.apartment:
        return Icons.apartment;
      case UnitType.house:
        return Icons.home;
      case UnitType.condo:
        return Icons.location_city;
      case UnitType.townhouse:
        return Icons.holiday_village;
      case UnitType.villa:
        return Icons.villa;
      case UnitType.penthouse:
        return Icons.roofing;
      case UnitType.duplex:
        return Icons.home_work;
      case UnitType.office:
        return Icons.business;
      case UnitType.shop:
        return Icons.storefront;
      case UnitType.warehouse:
        return Icons.warehouse;
      case UnitType.other:
        return Icons.other_houses;
    }
  }

  Widget _buildInlineSuggestions() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _searchResults.length,
        itemBuilder: (ctx, index) {
          final result = _searchResults[index];
          return InkWell(
            onTap: () => _onSuggestionSelected(result),
            borderRadius: index == 0
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : index == _searchResults.length - 1
                ? const BorderRadius.vertical(bottom: Radius.circular(12))
                : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(result.type),
                    size: 20,
                    color: _getTypeColor(result.type),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          result.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getTypeColor(result.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getTypeLabel(result.type),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _getTypeColor(result.type),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showIdOptionsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'What would you like to do?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.camera_alt, color: Colors.green.shade700),
                ),
                title: const Text('I found someone\'s ID'),
                subtitle: const Text('Scan & register a found ID'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FoundIdScanPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: Icon(Icons.search, color: Colors.orange.shade700),
                ),
                title: const Text('I lost my ID'),
                subtitle: const Text('Search if someone found it'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SearchLostIdPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onRentalTap(Rental rental) async {
    await _showInterstitialIfDue();

    // Record the interaction for FYP
    if (rental.id != null) {
      _prefsService?.recordRentalView(
        rentalId: rental.id!,
        city: rental.city,
        state: rental.state,
        bedrooms: rental.bedrooms,
        price: rental.price,
      );

      // Fresh-First TikTok-Style: mark as viewed when opening detail page
      _impressionService?.recordView(rental.id!);
      _dwellTimers[rental.id!]?.cancel();
      _dwellTimers.remove(rental.id!);
      setState(() {
        _clickedRentalIds.add(rental.id!);
        _viewedTimestamps[rental.id!] = DateTime.now().millisecondsSinceEpoch;
      });
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => RentalDetailPage(rental: rental)),
    );
    // Refresh saved ids when returning (user may have saved/unsaved from detail page)
    _loadSavedIds();
  }

  @override
  Widget build(BuildContext context) {
    if (_prefsService?.useTikTokStyle ?? false) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            _buildTikTokFeed(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text(
                        'TikTok Feed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: () {
                          // Could implement search or close TikTok view
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header is wrapped in Flexible + SingleChildScrollView so it cannot
            // overflow the outer Column on small screens or when the keyboard is open.
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header and Search — hides on scroll up, shows on scroll down
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: _isHeaderVisible
                            ? AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: 1.0,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    2,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TelegramTopBar(
                                        title: 'Find Your Home',
                                        actions: [
                                          IconButton(
                                            tooltip: 'Premium Map Radar',
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const MapExplorePage(),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.radar,
                                              color: Colors.green,
                                            ),
                                          ),
                                          const TopNotificationBell(),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      // Search Bar
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ValueListenableBuilder<String>(
                                                  valueListenable:
                                                      _typewriterNotifier,
                                                  builder: (context, twText, _) {
                                                    return TextField(
                                                      controller:
                                                          _searchController,
                                                      focusNode:
                                                          _searchFocusNode,
                                                      decoration: InputDecoration(
                                                        hintText:
                                                            _isDetectingLocation
                                                            ? 'Getting your location...'
                                                            : _searchController
                                                                  .text
                                                                  .isEmpty
                                                            ? (_searchFocusNode
                                                                      .hasFocus
                                                                  ? 'Search ward, area or constituency...'
                                                                  : (twText.isNotEmpty
                                                                        ? twText
                                                                        : 'Search location...'))
                                                            : null,
                                                        prefixIcon:
                                                            _isDetectingLocation
                                                            ? const Padding(
                                                                padding:
                                                                    EdgeInsets.all(
                                                                      12,
                                                                    ),
                                                                child: SizedBox(
                                                                  width: 20,
                                                                  height: 20,
                                                                  child:
                                                                      DwellyOrbitingLoader(),
                                                                ),
                                                              )
                                                            : IconButton(
                                                                icon: Icon(
                                                                  Icons.search,
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.primary,
                                                                ),
                                                                tooltip:
                                                                    'Search locations',
                                                                onPressed: () =>
                                                                    _searchFocusNode
                                                                        .requestFocus(),
                                                              ),
                                                        suffixIcon:
                                                            _searchController
                                                                .text
                                                                .isNotEmpty
                                                            ? IconButton(
                                                                icon: const Icon(
                                                                  Icons.clear,
                                                                ),
                                                                onPressed: () {
                                                                  _searchController
                                                                      .clear();
                                                                  setState(
                                                                    () =>
                                                                        _searchResults =
                                                                            [],
                                                                  );
                                                                  _onSearch('');
                                                                },
                                                              )
                                                            : IconButton(
                                                                icon: const Icon(
                                                                  Icons
                                                                      .camera_alt_outlined,
                                                                ),
                                                                tooltip:
                                                                    'Lost & Found ID',
                                                                onPressed:
                                                                    _showIdOptionsDialog,
                                                              ),
                                                        border: OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        filled: true,
                                                        fillColor:
                                                            Theme.of(
                                                                  context,
                                                                ).brightness ==
                                                                Brightness.dark
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .surfaceContainerHighest
                                                                  .withOpacity(
                                                                    0.55,
                                                                  )
                                                            : Colors.grey[100],
                                                        contentPadding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 16,
                                                              vertical: 12,
                                                            ),
                                                      ),
                                                      onChanged:
                                                          _onSearchTextChanged,
                                                      onSubmitted: _onSearch,
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // Filter Button
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: _filters.hasFilters
                                                      ? Theme.of(
                                                          context,
                                                        ).primaryColor
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: IconButton(
                                                  icon: Icon(
                                                    Icons.tune,
                                                    color: _filters.hasFilters
                                                        ? Colors.white
                                                        : Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                  ),
                                                  onPressed: () => setState(() {
                                                    _showFilters =
                                                        !_showFilters;
                                                  }),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // My Location Button
                                              Container(
                                                decoration: BoxDecoration(
                                                  color:
                                                      (_deviceLocation !=
                                                              null &&
                                                          _searchArea ==
                                                              _deviceLocation!
                                                                  .displayName)
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: IconButton(
                                                  onPressed:
                                                      _isDetectingLocation
                                                      ? null
                                                      : () async {
                                                          setState(
                                                            () =>
                                                                _isDetectingLocation =
                                                                    true,
                                                          );
                                                          final result =
                                                              await DeviceLocationService.getCurrentLocation();

                                                          if (!mounted) return;
                                                          setState(
                                                            () =>
                                                                _isDetectingLocation =
                                                                    false,
                                                          );

                                                          if (result.success &&
                                                              result
                                                                  .hasLocationData) {
                                                            setState(() {
                                                              _deviceLocation =
                                                                  result;
                                                              _searchArea = result
                                                                  .displayName;
                                                              _searchController
                                                                  .text = result
                                                                  .displayName;
                                                              _useFYP = false;
                                                            });
                                                            if (result
                                                                .isOutsideKenya) {
                                                              setState(() {
                                                                _invalidateFeedCache();
                                                                _rentals = [];
                                                                _isLoading =
                                                                    false;
                                                                _error = null;
                                                                _hasMore =
                                                                    false;
                                                              });
                                                              return;
                                                            }
                                                            _refreshLocationAwareAds();
                                                            _loadRentals(
                                                              refresh: true,
                                                            );
                                                          } else {
                                                            ScaffoldMessenger.of(
                                                              context,
                                                            ).showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                  result.errorMessage ??
                                                                      'Failed to get location. Please check your permissions.',
                                                                ),
                                                                backgroundColor:
                                                                    Colors.red,
                                                              ),
                                                            );
                                                          }
                                                        },
                                                  tooltip: 'Use my location',
                                                  icon: _isDetectingLocation
                                                      ? const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              DwellyOrbitingLoader(),
                                                        )
                                                      : Icon(
                                                          (_deviceLocation !=
                                                                      null &&
                                                                  _searchArea ==
                                                                      _deviceLocation!
                                                                          .displayName)
                                                              ? Icons
                                                                    .my_location
                                                              : Icons
                                                                    .location_searching,
                                                          color:
                                                              (_deviceLocation !=
                                                                      null &&
                                                                  _searchArea ==
                                                                      _deviceLocation!
                                                                          .displayName)
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary
                                                              : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Inline search suggestions
                                      if (_searchResults.isNotEmpty &&
                                          _searchFocusNode.hasFocus)
                                        _buildInlineSuggestions(),
                                      // Nearby areas chips (only when header visible)
                                      if (_nearbyAreas.isNotEmpty &&
                                          _searchArea != null) ...[
                                        const SizedBox(height: 12),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              Text(
                                                'Nearby: ',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              ..._nearbyAreas
                                                  .take(5)
                                                  .map(
                                                    (area) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 8,
                                                          ),
                                                      child: ActionChip(
                                                        label: Text(
                                                          LocationService.formatAreaName(
                                                            area,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: colorScheme
                                                                .onSecondaryContainer,
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          _searchController
                                                                  .text =
                                                              LocationService.formatAreaName(
                                                                area,
                                                              );
                                                          _onSearch(area);
                                                        },
                                                        backgroundColor: colorScheme
                                                            .secondaryContainer,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                    ),
                                                  ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (_borderNeighborAreas.isNotEmpty &&
                                          _searchArea != null) ...[
                                        const SizedBox(height: 8),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              Text(
                                                'Border: ',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              ..._borderNeighborAreas
                                                  .take(5)
                                                  .map(
                                                    (area) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 8,
                                                          ),
                                                      child: ActionChip(
                                                        label: Text(
                                                          LocationService.formatAreaName(
                                                            area,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: colorScheme
                                                                .onTertiaryContainer,
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          _searchController
                                                                  .text =
                                                              LocationService.formatAreaName(
                                                                area,
                                                              );
                                                          _onSearch(area);
                                                        },
                                                        backgroundColor:
                                                            colorScheme
                                                                .tertiaryContainer,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                    ),
                                                  ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ), // end AnimatedOpacity
                              )
                            : const SizedBox.shrink(),
                      ), // end AnimatedSize for header
                      if (!_searchFocusNode.hasFocus) _buildServicesRow(),
                      // Location info banner + filter chips — also hide on scroll or when searching
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: (_isHeaderVisible && !_searchFocusNode.hasFocus)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Location info banner
                                  if ((_searchArea != null &&
                                          _searchArea!.isNotEmpty) ||
                                      _activeAnchorLabel() != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (_deviceLocation != null &&
                                                  _searchArea ==
                                                      _deviceLocation!
                                                          .displayName)
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withOpacity(0.5)
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .secondaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              (_deviceLocation != null &&
                                                      _searchArea ==
                                                          _deviceLocation!
                                                              .displayName)
                                                  ? Icons.my_location
                                                  : Icons.location_on,
                                              size: 16,
                                              color:
                                                  (_deviceLocation != null &&
                                                      _searchArea ==
                                                          _deviceLocation!
                                                              .displayName)
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                (_activeAnchorLabel() != null &&
                                                        _activeAnchorLabel()!
                                                            .trim()
                                                            .isNotEmpty)
                                                    ? 'Showing results near ${_activeAnchorLabel()!}'
                                                    : ((_deviceLocation !=
                                                                  null &&
                                                              _searchArea ==
                                                                  _deviceLocation!
                                                                      .displayName)
                                                          ? 'Showing rentals near you'
                                                          : 'Showing results'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          (_deviceLocation !=
                                                                  null &&
                                                              _searchArea ==
                                                                  _deviceLocation!
                                                                      .displayName)
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSecondaryContainer,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_searchExhausted &&
                                      (_nextAction == 'BROADEN_SCOPE') &&
                                      (_activeAnchorLabel() != null))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'No more rentals in this radius.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                if (_anchorConstituency !=
                                                        null &&
                                                    _anchorConstituency!
                                                        .isNotEmpty)
                                                  ActionChip(
                                                    label: const Text(
                                                      'Broaden to constituency',
                                                    ),
                                                    onPressed:
                                                        _broadenToConstituency,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                if (_anchorCounty != null &&
                                                    _anchorCounty!.isNotEmpty)
                                                  ActionChip(
                                                    label: const Text(
                                                      'Broaden to county',
                                                    ),
                                                    onPressed: _broadenToCounty,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                ActionChip(
                                                  label: const Text(
                                                    'Show all Kenya',
                                                  ),
                                                  onPressed: _showAllKenya,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ), // end AnimatedSize for location + filter chips
                      if (!_showFilters && !_searchFocusNode.hasFocus) ...[
                        // Active Filters
                        if (_filters.hasFilters)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_filters.minPrice != null ||
                                    _filters.maxPrice != null)
                                  Chip(
                                    label: Text(
                                      'KES ${_filters.minPrice?.toInt() ?? 0} - KES ${_filters.maxPrice?.toInt() ?? '∞'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        _priceRange = RangeValues(
                                          _minPrice,
                                          _maxPrice,
                                        );
                                        _filters = _filters.copyWith(
                                          minPrice: null,
                                          maxPrice: null,
                                        );
                                      });
                                      _loadRentals(refresh: true);
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (_filters.bedrooms != null)
                                  Chip(
                                    label: Text(
                                      '${_filters.bedrooms} BR',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedBedrooms = null;
                                        _filters = _filters.copyWith(
                                          bedrooms: null,
                                        );
                                      });
                                      _loadRentals(refresh: true);
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (_filters.propertyType != null)
                                  Chip(
                                    label: Text(
                                      _selectedPropertyType?.label ??
                                          _filters.propertyType!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedPropertyType = null;
                                        _filters = RentalFilters(
                                          area: _filters.area,
                                          constituency: _filters.constituency,
                                          nearbyAreas: _filters.nearbyAreas,
                                          minPrice: _filters.minPrice,
                                          maxPrice: _filters.maxPrice,
                                          bedrooms: _filters.bedrooms,
                                          bathrooms: _filters.bathrooms,
                                        );
                                      });
                                      _loadRentals(refresh: true);
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (_filters.constituency != null &&
                                    _filters.constituency!.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      _filters.constituency!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedConstituency = null;
                                        _filters = RentalFilters(
                                          area: _filters.area,
                                          nearbyAreas: _filters.nearbyAreas,
                                          minPrice: _filters.minPrice,
                                          maxPrice: _filters.maxPrice,
                                          bedrooms: _filters.bedrooms,
                                          bathrooms: _filters.bathrooms,
                                          propertyType: _filters.propertyType,
                                          expandedBedrooms:
                                              _filters.expandedBedrooms,
                                        );
                                      });
                                      _loadRentals(refresh: true);
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                TextButton(
                                  onPressed: _clearFilters,
                                  child: const Text(
                                    'Clear all',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (_showHelperBanner)
                          _HouseSearchHelpBanner(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HelperHubPage(),
                                ),
                              );
                            },
                            onClose: _dismissHelperBanner,
                          ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ), // end inner Column
                ), // end SingleChildScrollView
              ), // end ConstrainedBox
            ), // end Flexible header
            // Filter Panel OR Content
            if (_showFilters)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildFilterPanel(),
                ),
              )
            else
              Expanded(
                child: Stack(
                  children: [
                    _buildContent(),
                    if (_newPropertiesAvailableCount > 0)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(24),
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                setState(
                                  () => _newPropertiesAvailableCount = 0,
                                );
                                _scrollController.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                                _loadRentals(refresh: true);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome,
                                      size: 18,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$_newPropertiesAvailableCount new ${_newPropertiesAvailableCount == 1 ? 'property' : 'properties'} available — Tap to refresh',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
  }

  String _formatKes(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble()
          ? 'KES ${k.toInt()}K'
          : 'KES ${k.toStringAsFixed(1)}K';
    }
    return 'KES ${value.toInt()}';
  }

  List<String> _getConstituencyOptions() {
    final options = <String>{};
    final county = _deviceLocation?.county;
    if (county != null && county.isNotEmpty) {
      options.addAll(KenyaLocations.getConstituencies(county));
    }
    for (final constituencies in KenyaLocations.constituenciesByCounty.values) {
      options.addAll(constituencies);
    }
    final list = options.toList();
    list.sort();
    return list;
  }

  Widget _buildFilterPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.1,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_locationFilterAd != null && _adService != null) ...[
            BannerAdWidget(
              ad: _locationFilterAd!,
              adService: _adService!,
              height: 140,
            ),
            const SizedBox(height: 16),
          ],
          // Price Range
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price Range',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                'KES ${_formatKes(_priceRange.start)} - ${_formatKes(_priceRange.end)}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          RangeSlider(
            values: _priceRange,
            min: _minPrice,
            max: _maxPrice,
            divisions: 100,
            labels: RangeLabels(
              _formatKes(_priceRange.start),
              _formatKes(_priceRange.end),
            ),
            onChanged: (values) => setState(() => _priceRange = values),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KES 0',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'KES 100K',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Property Type
          Text(
            'Property Type',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: UnitType.values.map((type) {
              final isSelected = _selectedPropertyType == type;
              return ChoiceChip(
                avatar: isSelected
                    ? null
                    : Icon(_getUnitTypeIcon(type), size: 16),
                label: Text(type.label),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedPropertyType = selected ? type : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Constituency',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('constituency-${_selectedConstituency ?? 'any'}'),
            initialValue: _selectedConstituency,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Any constituency',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Any constituency'),
              ),
              ..._getConstituencyOptions().map(
                (constituency) => DropdownMenuItem<String>(
                  value: constituency,
                  child: Text(constituency, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedConstituency = value;
              });
            },
          ),
          const SizedBox(height: 16),
          // Bedrooms
          Text(
            'Bedrooms',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _bedroomOptions.map((count) {
              final isSelected = _selectedBedrooms == count;
              return ChoiceChip(
                label: Text(count == 0 ? 'Studio' : '$count BR'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedBedrooms = selected ? count : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _applyFilters,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _rentals.isEmpty) {
      return const Center(child: DwellyOrbitingLoader(size: 72));
    }

    if (_error != null && _rentals.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Failed to load rentals',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadRentals(refresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rentals.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _searchArea != null
                    ? 'No rentals found in $_searchArea'
                    : 'No rentals available',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                _searchArea != null
                    ? 'Try searching a different area or adjust filters'
                    : 'Check back later for new listings',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              if (_filters.hasFilters) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear Filters'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final listView = RefreshIndicator(
      key: _refreshIndicatorKey,
      onRefresh: () => _loadRentals(refresh: true),
      child: ListView.builder(
        // Offset itemCount by 1 if we're showing a recycled feed header
        // The header is inserted at index 0 in the builder below
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        itemCount: _getListItemCount(),
        itemBuilder: (context, index) {
          final itemInfo = _getItemAtIndex(index);

          if (itemInfo.isLoadingIndicator) {
            // Loading indicator at the bottom
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const DwellyOrbitingLoader()
                    : TextButton(
                        onPressed: _loadMoreRentals,
                        child: const Text('Load more'),
                      ),
              ),
            );
          }

          if (itemInfo.isAd && itemInfo.ad != null) {
            // Feed ad card
            return _FeedAdCard(
              key: ValueKey(
                'feed-ad-card-${itemInfo.adPlacement}-${itemInfo.ad!.id}-$index',
              ),
              ad: itemInfo.ad!,
              adService: _adService!,
              placement: itemInfo.adPlacement ?? AdPlacement.RENTAL_FEED.name,
              listIndex: index,
              county: _deviceLocation?.county,
              constituency: _deviceLocation?.constituency,
            );
          }

          if (itemInfo.isGoogleAd) {
            return _GoogleFeedAdCard(adService: _adService);
          }

          if (itemInfo.rental != null) {
            final rental = itemInfo.rental!;
            final rentalCard = _RentalCard(
              rental: rental,
              isEffectivelySponsored: _isEffectivelySponsored(rental),
              onTap: () => _onRentalTap(rental),
              searchArea: _searchArea,
              isSaved: rental.id != null && _savedRentalIds.contains(rental.id),
              isViewed:
                  rental.id != null && _clickedRentalIds.contains(rental.id),
              onToggleSave: () {
                if (rental.id != null) _toggleSaveRental(rental.id!);
              },
              onReport: () => _showReportDialog(rental),
              userLatitude: _deviceLocation?.latitude,
              userLongitude: _deviceLocation?.longitude,
            );

            // Wrap with VisibilityDetector for Fresh-First TikTok-Style impression tracking
            return VisibilityDetector(
              key: Key('impression-${rental.id ?? index}'),
              onVisibilityChanged: (info) {
                if (rental.id != null && !_isEffectivelySponsored(rental)) {
                  if (info.visibleFraction > 0.6) {
                    _impressionService?.recordImpression(rental.id!);
                    if (_isListingUnseen(rental) &&
                        !_dwellTimers.containsKey(rental.id!)) {
                      _dwellTimers[rental.id!] = Timer(
                        const Duration(milliseconds: 3500),
                        () {
                          if (mounted) {
                            _impressionService?.recordView(rental.id!);
                            setState(() {
                              _clickedRentalIds.add(rental.id!);
                              _viewedTimestamps[rental.id!] =
                                  DateTime.now().millisecondsSinceEpoch;
                            });
                            _dwellTimers.remove(rental.id!);
                          }
                        },
                      );
                    }
                  } else if (info.visibleFraction < 0.3) {
                    _dwellTimers[rental.id!]?.cancel();
                    _dwellTimers.remove(rental.id!);
                  }
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show recycled feed header before the first rental card
                  if (_isRecycledFeed && index == 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You\'ve seen all new listings. Here are listings you may want to revisit.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  rentalCard,
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );

    return listView;
  }

  /// Get total item count including ads and loading indicator
  int _getListItemCount() {
    return _buildFeedItems().length;
  }

  /// Get item info at a given list index, accounting for injected ads
  _ListItemInfo _getItemAtIndex(int index) {
    final items = _buildFeedItems();
    if (index < 0 || index >= items.length) {
      return _ListItemInfo(isLoadingIndicator: true);
    }
    return items[index];
  }

  List<_ListItemInfo> _buildFeedItems() {
    if (_cachedFeedItems != null) {
      return _cachedFeedItems!;
    }
    final items = <_ListItemInfo>[];
    final validRentalFeedPositions = _feedAdPositions
        .where(
          (position) =>
              position <= _rentals.length && _feedAds[position] != null,
        )
        .toSet();
    final contextAd = _hasSearchContext
        ? _searchResultsAd
        : (!_filters.hasFilters ? _homeBannerAd : null);
    final contextPlacement = _hasSearchContext
        ? AdPlacement.SEARCH_RESULTS.name
        : AdPlacement.HOME_BANNER.name;

    int nonSponsoredCount = 0;
    int listingsSinceLastAd = 0;

    for (int i = 0; i < _rentals.length; i++) {
      final rental = _rentals[i];
      final oneBasedPosition = i + 1;

      items.add(_ListItemInfo(rental: rental));
      listingsSinceLastAd++;

      if (!_isEffectivelySponsored(rental)) {
        nonSponsoredCount++;
      }

      // Enforce clean pacing: never show an ad within the first 4 listings,
      // and ensure at least 6 real listings between any two ads!
      if (oneBasedPosition >= 5 && listingsSinceLastAd >= 6) {
        bool adInserted = false;

        // 1. Priority to targeted rental feed positions from backend
        if (validRentalFeedPositions.contains(oneBasedPosition)) {
          final beforeCount = items.length;
          _appendAdItem(
            items,
            _feedAds[oneBasedPosition],
            AdPlacement.RENTAL_FEED.name,
          );
          if (items.length > beforeCount) {
            adInserted = true;
          }
        }

        // 2. Or context banner ad (every ~18 listings)
        if (!adInserted && contextAd != null && oneBasedPosition % 18 == 0) {
          final beforeCount = items.length;
          _appendAdItem(items, contextAd, contextPlacement);
          if (items.length > beforeCount) {
            adInserted = true;
          }
        }

        // 3. Or home feed banner ad (every ~24 listings)
        if (!adInserted &&
            _canShowHomeFeedAd &&
            _homeFeedAd != null &&
            oneBasedPosition % 24 == 0) {
          final beforeCount = items.length;
          _appendAdItem(items, _homeFeedAd, AdPlacement.HOME_FEED.name);
          if (items.length > beforeCount) {
            adInserted = true;
          }
        }

        // 4. Or Google AdBanner (spaced out to every 6 non-sponsored listings instead of 3)
        if (!adInserted && !_isEffectivelySponsored(rental) && nonSponsoredCount % 6 == 0) {
          items.add(_ListItemInfo(isGoogleAd: true));
          adInserted = true;
        }

        if (adInserted) {
          listingsSinceLastAd = 0;
        }
      }
    }

    if (_hasMore) {
      items.add(_ListItemInfo(isLoadingIndicator: true));
    }

    _cachedFeedItems = items;
    return items;
  }

  void _appendAdItem(
    List<_ListItemInfo> items,
    Advertisement? ad,
    String placement,
  ) {
    if (ad == null) return;

    final previous = items.isNotEmpty ? items.last : null;
    if (previous != null &&
        previous.isAd &&
        previous.ad?.id == ad.id &&
        previous.adPlacement == placement) {
      return;
    }

    items.add(_ListItemInfo(isAd: true, ad: ad, adPlacement: placement));
  }

  Widget _buildServicesRow() {
    final theme = Theme.of(context);
    final categoriesToShow = kServiceCategoriesList
        .where((c) => c.name != "All")
        .toList();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categoriesToShow.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isViewAll = index == categoriesToShow.length;
          final cat = isViewAll ? null : categoriesToShow[index];

          return Center(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ServicesListPage(
                      initialCategory: isViewAll ? "All" : cat!.name,
                    ),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isViewAll
                      ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.3,
                        )
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isViewAll
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  isViewAll ? 'View All' : cat!.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isViewAll ? FontWeight.bold : FontWeight.w600,
                    color: isViewAll
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onPageChanged(int index) {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    setState(() => _currentPageIndex = index);

    if (index >= _getListItemCount() - 3) {
      _loadMoreRentals();
    }

    final itemInfo = _getItemAtIndex(index);
    if (itemInfo.rental != null &&
        itemInfo.rental!.id != null &&
        !_isEffectivelySponsored(itemInfo.rental!)) {
      final rental = itemInfo.rental!;
      _impressionService?.recordImpression(rental.id!);
      if (_isListingUnseen(rental) && !_dwellTimers.containsKey(rental.id!)) {
        _dwellTimers[rental.id!] = Timer(
          const Duration(milliseconds: 3500),
          () {
            if (mounted && _currentPageIndex == index) {
              _impressionService?.recordView(rental.id!);
              setState(() {
                _clickedRentalIds.add(rental.id!);
                _viewedTimestamps[rental.id!] =
                    DateTime.now().millisecondsSinceEpoch;
              });
              _dwellTimers.remove(rental.id!);
            }
          },
        );
      }
    }
    _prefetchUpcomingRentals(index.clamp(0, _rentals.isNotEmpty ? _rentals.length - 1 : 0));
  }

  Widget _buildTikTokFeed() {
    if (_isLoading && _rentals.isEmpty) {
      return Center(
        child: DwellyOrbitingLoader(
          glowColor: Theme.of(context).primaryColor,
          size: 60,
        ),
      );
    }

    if (_error != null && _rentals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadRentals(refresh: true),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_rentals.isEmpty) {
      return const Center(child: Text('No rentals found.'));
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPageChanged,
      itemCount: _getListItemCount(),
      itemBuilder: (context, index) {
        final itemInfo = _getItemAtIndex(index);

        if (itemInfo.isAd && itemInfo.ad != null) {
          return Container(
            color: Colors.black,
            child: Center(
              child: BannerAdWidget(
                ad: itemInfo.ad!,
                adService: _adService!,
              ),
            ),
          );
        }

        if (itemInfo.isGoogleAd) {
          return Container(
            color: Colors.black,
            child: Center(
              child: _GoogleFeedAdCard(adService: _adService),
            ),
          );
        }

        if (itemInfo.rental != null) {
          final rental = itemInfo.rental!;
          return TikTokRentalPage(
            key: ValueKey('tiktok-${rental.id ?? index}'),
            rental: rental,
            isEffectivelySponsored: _isEffectivelySponsored(rental),
            onTapDetails: () => _onRentalTap(rental),
            isSaved: rental.id != null && _savedRentalIds.contains(rental.id),
            isViewed: rental.id != null && _clickedRentalIds.contains(rental.id),
            onToggleSave: () {
              if (rental.id != null) _toggleSaveRental(rental.id!);
            },
            onReport: () => _showReportDialog(rental),
            userLatitude: _deviceLocation?.latitude,
            userLongitude: _deviceLocation?.longitude,
            isActivePage: index == _currentPageIndex,
          );
        }
        
        return const SizedBox.shrink();
      }
    );
  }
}

class _HouseSearchHelpBanner extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _HouseSearchHelpBanner({required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Material(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 32, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.manage_search,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Need someone to search for you?',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'See available helpers and their rates.',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.78,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                size: 18,
                color: colorScheme.onPrimaryContainer.withOpacity(0.5),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper class to identify item type in list
class _ListItemInfo {
  final bool isAd;
  final bool isGoogleAd;
  final bool isLoadingIndicator;
  final bool isServicesRow;
  final Advertisement? ad;
  final String? adPlacement;
  final Rental? rental;

  _ListItemInfo({
    this.isAd = false,
    this.isGoogleAd = false,
    this.isLoadingIndicator = false,
    this.isServicesRow = false,
    this.ad,
    this.adPlacement,
    this.rental,
  });
}

/// Feed ad card displayed in rental list
class _FeedAdCard extends StatefulWidget {
  final Advertisement ad;
  final AdService adService;
  final String placement;
  final int listIndex;
  final String? county;
  final String? constituency;

  const _FeedAdCard({
    super.key,
    required this.ad,
    required this.adService,
    required this.placement,
    required this.listIndex,
    this.county,
    this.constituency,
  });

  @override
  State<_FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<_FeedAdCard> {
  static const double _enterVisibleThreshold = 0.6;
  static const double _exitVisibleThreshold = 0.05;
  bool _encounterActive = false;

  void _onVisibilityChanged(VisibilityInfo info) {
    final visibleFraction = info.visibleFraction;

    if (!_encounterActive && visibleFraction >= _enterVisibleThreshold) {
      _encounterActive = true;
      widget.adService.recordAnalyticsEvent(
        adId: widget.ad.id,
        eventType: 'IMPRESSION',
        county: widget.county,
        constituency: widget.constituency,
        placement: widget.placement,
      );
      return;
    }

    if (_encounterActive && visibleFraction <= _exitVisibleThreshold) {
      _encounterActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VisibilityDetector(
      key: Key(
        'feed-ad-visibility-${widget.placement}-${widget.ad.id}-${widget.listIndex}',
      ),
      onVisibilityChanged: _onVisibilityChanged,
      child: Card(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: () => _onTap(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ad image matching listing card 16:9 aspect ratio exactly
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: widget.ad.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.ad.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                _buildPlaceholder(),
                            placeholder: (context, url) =>
                                const ShimmerPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                  if (widget.ad.advertiserVerified)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Ad content layout matching listing card exactly (avatar circle + column)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.campaign,
                        color: theme.colorScheme.onPrimaryContainer,
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
                                  widget.ad.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Sponsored',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Promoted • ${_getCtaLabel()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.ad.advertiserName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.ad.description != null &&
                              widget.ad.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.ad.description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
      ),
    );
  }

  void _onTap(BuildContext context) {
    // Record click
    widget.adService.recordAnalyticsEvent(
      adId: widget.ad.id,
      eventType: 'CLICK',
      county: widget.county,
      constituency: widget.constituency,
      placement: widget.placement,
    );
    // Open URL if available
    final launchUrlValue =
        widget.ad.displayUrl ??
        widget.ad.targetUrl ??
        widget.ad.playStoreUrl ??
        widget.ad.appStoreUrl;
    if (launchUrlValue != null && launchUrlValue.isNotEmpty) {
      _launchUrl(launchUrlValue);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  /// Get CTA button label based on link type
  String _getCtaLabel() {
    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        return 'Visit';
      case LinkType.PLAYSTORE:
      case LinkType.APPSTORE:
      case LinkType.APP_BOTH:
        return 'Download';
      case LinkType.FORM:
        return widget.ad.formSubmitButtonText ?? 'Submit';
      case LinkType.NONE:
        return 'Learn More';
    }
  }
}

class _GoogleFeedAdCard extends StatefulWidget {
  final AdService? adService;

  const _GoogleFeedAdCard({super.key, this.adService});

  @override
  State<_GoogleFeedAdCard> createState() => _GoogleFeedAdCardState();
}

class _GoogleFeedAdCardState extends State<_GoogleFeedAdCard> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isAdLoadStarted = false;
  Advertisement? _cachedFallbackAd;
  AdService? _resolvedAdService;

  @override
  void initState() {
    super.initState();
    _resolvedAdService = widget.adService;
    _checkCachedOrLoad();
  }

  Future<void> _checkCachedOrLoad() async {
    _resolvedAdService ??= await AdService.getInstance();
    if (_resolvedAdService != null) {
      final ad = await _resolvedAdService!.getCachedOrStaleAd(
        AdPlacement.RENTAL_FEED,
      );
      if (mounted && ad != null) {
        setState(() {
          _cachedFallbackAd = ad;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isAdLoadStarted &&
        !kIsWeb &&
        (Platform.isIOS || Platform.isAndroid)) {
      final isPremium = AuthService.currentUser?.isPremiumActive ?? false;
      if (!isPremium) {
        _isAdLoadStarted = true;
        _loadAd(MediaQuery.of(context).size.width.truncate());
      }
    }
  }

  Future<void> _loadAd(int width) async {
    final adSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width) ??
        AdSize.mediumRectangle;
    _bannerAd = BannerAd(
      adUnitId: GoogleAdService.bannerAdUnitId,
      request: const AdRequest(),
      size: adSize,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('Google feed BannerAd failed to load: $err');
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = AuthService.currentUser?.isPremiumActive ?? false;
    if (isPremium) {
      return const SizedBox.shrink();
    }

    // If Google ad failed to load, check cached ad pool as requested:
    // "cache google ads whenever google doesn't send ad use those even if they don't generate revenue"
    if (!_isLoaded || _bannerAd == null) {
      if (_cachedFallbackAd != null &&
          _cachedFallbackAd!.shouldDisplay &&
          _resolvedAdService != null) {
        return _FeedAdCard(
          ad: _cachedFallbackAd!,
          adService: _resolvedAdService!,
          placement: AdPlacement.RENTAL_FEED.name,
          listIndex: 0,
        );
      }
      return (DateTime.now().second % 2 == 0)
          ? const _PremiumPromoFeedCard()
          : const _DeveloperPromoFeedCard();
    }

    // If Google ad loaded, display it inside the exact same size card as a listing card
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              child: Center(
                child: SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.campaign,
                    color: theme.colorScheme.onPrimaryContainer,
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
                              'Sponsored Partner Ad',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Sponsored',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Verified Partner • Google Ads',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Promoted Offer',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumPromoFeedCard extends StatelessWidget {
  const _PremiumPromoFeedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0EA5E9), Color(0xFF1E40AF)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.workspace_premium,
                        size: 64,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'DWELLY PREMIUM 👑',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '100% Ad-Free • Verified Owner Contacts • Instant Alerts',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.amber.shade100,
                    child: Icon(Icons.star, color: Colors.amber.shade800),
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
                                'Upgrade to Dwelly Premium',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'AD-FREE',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Exclusive VIP Perks & Instant Contact Access',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Unlock direct owner phone numbers, WhatsApp notifications, 7-day temporary chat privileges, and browse all listings without any ads.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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

class _DeveloperPromoFeedCard extends StatelessWidget {
  const _DeveloperPromoFeedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AboutDeveloperPage()));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF312E81)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.code_rounded,
                        size: 64,
                        color: Colors.cyanAccent,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'NEED A CUSTOM APP? ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Websites • Mobile Apps • Custom Software Solutions',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.indigo.shade100,
                    child: Icon(
                      Icons.developer_mode,
                      color: Colors.indigo.shade800,
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
                                'Need a Website, Software or Mobile App?',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'HIRE US',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Reach out to the Dwelly Developer directly via Socials',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Looking for high-quality website development, custom software, or iOS/Android apps? Tap to connect on WhatsApp, LinkedIn, X, GitHub & more.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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

class _RentalCard extends StatefulWidget {
  final Rental rental;
  final bool isEffectivelySponsored;
  final VoidCallback onTap;
  final String? searchArea;
  final bool isSaved;
  final bool isViewed;
  final VoidCallback onToggleSave;
  final VoidCallback onReport;
  final double? userLatitude;
  final double? userLongitude;

  const _RentalCard({
    required this.rental,
    this.isEffectivelySponsored = false,
    required this.onTap,
    this.searchArea,
    required this.isSaved,
    this.isViewed = false,
    required this.onToggleSave,
    required this.onReport,
    this.userLatitude,
    this.userLongitude,
  });

  @override
  State<_RentalCard> createState() => _RentalCardState();
}

class _RentalCardState extends State<_RentalCard> {
  VideoPlayerController? _videoController;
  VideoPlayerController? _compoundVideoController;
  bool _showHashtags = false;
  String? _cachedDistanceText;

  @override
  void initState() {
    super.initState();
    _computeDistanceText();
    // Delay video initialization slightly (250ms) so fast scrolling
    // doesn't hitch or stutter trying to open network sockets mid-scroll!
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _initVideos();
      }
    });
  }

  @override
  void didUpdateWidget(_RentalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userLatitude != widget.userLatitude ||
        oldWidget.userLongitude != widget.userLongitude ||
        oldWidget.rental.latitude != widget.rental.latitude ||
        oldWidget.rental.longitude != widget.rental.longitude) {
      _computeDistanceText();
    }
  }

  void _computeDistanceText() {
    if (widget.userLatitude != null &&
        widget.userLongitude != null &&
        widget.rental.latitude != null &&
        widget.rental.longitude != null) {
      final distanceMeters = Geolocator.distanceBetween(
        widget.userLatitude!,
        widget.userLongitude!,
        widget.rental.latitude!,
        widget.rental.longitude!,
      );
      if (distanceMeters < 1000) {
        _cachedDistanceText = '${distanceMeters.toStringAsFixed(0)}m away';
      } else {
        _cachedDistanceText = '${(distanceMeters / 1000).toStringAsFixed(1)}km away';
      }
    } else {
      _cachedDistanceText = null;
    }
  }

  void _initVideos() {
    // Compound video: always initialize & autoplay preview for all users ("even a non premium user can see it... no matter how many cards are set to be displayed")
    if (widget.rental.compoundVideoUrl != null &&
        widget.rental.compoundVideoUrl!.isNotEmpty) {
      _compoundVideoController =
          VideoPlayerController.networkUrl(
              Uri.parse(widget.rental.compoundVideoUrl!),
            )
            ..initialize().then((_) {
              _compoundVideoController!.setVolume(0);
              _compoundVideoController!.setLooping(true);
              _compoundVideoController!.play();
              if (mounted) setState(() {});
            });
    }

    if (widget.rental.hasVideo &&
        widget.rental.cardDisplayPreference == 'VIDEO' &&
        widget.rental.videoUrl != null) {
      final isUnlocked = VideoUnlockSessionService.isVideoUnlocked(
        rentalId: widget.rental.id,
        videoUrl: widget.rental.videoUrl,
      );
      if (isUnlocked) {
        _videoController =
            VideoPlayerController.networkUrl(Uri.parse(widget.rental.videoUrl!))
              ..initialize().then((_) {
                _videoController!.setVolume(0);
                _videoController!.setLooping(true);
                _videoController!.play();
                if (mounted) setState(() {});
              });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _compoundVideoController?.dispose();
    super.dispose();
  }

  bool get _isExactMatch {
    if (widget.searchArea == null) return false;
    return widget.rental.city.toLowerCase() == widget.searchArea!.toLowerCase();
  }

  bool get _isNearbyMatch {
    if (widget.searchArea == null || _isExactMatch) return false;
    final nearbyAreas = LocationService.getNearbyAreas(widget.searchArea!);
    return nearbyAreas.any(
      (area) => widget.rental.city.toLowerCase().contains(area.toLowerCase()),
    );
  }

  Widget _buildCompoundVideoOverlay(BuildContext context) {
    if (_compoundVideoController == null ||
        !_compoundVideoController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: 10,
      right: 10,
      child: GestureDetector(
        onTap: () => _handleCompoundVideoClick(context),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 6, spreadRadius: 1),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(_compoundVideoController!),
              Positioned(
                bottom: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCompoundVideoClick(BuildContext context) async {
    final isUnlocked = VideoUnlockSessionService.isVideoUnlocked(
      rentalId: widget.rental.id,
      videoUrl: widget.rental.compoundVideoUrl,
    );

    if (isUnlocked) {
      _openFullScreenCompoundVideo();
    } else {
      await GoogleRewardedAdManager.showRewardedAd(
        context,
        onReward: () {
          if (mounted) {
            VideoUnlockSessionService.unlockVideo(
              rentalId: widget.rental.id,
              videoUrl: widget.rental.compoundVideoUrl,
            );
            _openFullScreenCompoundVideo();
          }
        },
      );
    }
  }

  void _openFullScreenCompoundVideo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenGallery(
          rentalId: widget.rental.id,
          imageUrls: widget.rental.imageUrls,
          thumbnailUrls: widget.rental.thumbnailUrls,
          mediumUrls: widget.rental.mediumUrls,
          videoUrl: widget.rental.compoundVideoUrl,
          showVideoFirst: true,
          isPremium: true,
        ),
      ),
    );
  }

  Widget _buildMediaArea(BuildContext context) {
    if (widget.rental.imageUrls.isEmpty && widget.rental.thumbnailUrls.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildImageFallback(context),
      );
    }

    final cardWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      200.0,
      1200.0,
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fullCacheW = (cardWidth * dpr).round().clamp(1, 1600);
    final fullCacheH = ((cardWidth * 9 / 16) * dpr).round().clamp(1, 1000);
    final halfCacheW = (fullCacheW / 2).round().clamp(1, 1200);
    final twoThirdsCacheW = (fullCacheW * 0.66).round().clamp(1, 1400);
    final oneThirdCacheW = (fullCacheW - twoThirdsCacheW).clamp(1, 1000);
    final halfCacheH = (fullCacheH / 2).round().clamp(1, 700);

    String? thumbAt(int i) => i < widget.rental.thumbnailUrls.length
        ? widget.rental.thumbnailUrls[i]
        : null;

    Widget baseLayout;
    if (widget.rental.hasVideo) {
      final isUnlocked = VideoUnlockSessionService.isVideoUnlocked(
        rentalId: widget.rental.id,
        videoUrl: widget.rental.videoUrl,
      );
      if (widget.rental.cardDisplayPreference == 'VIDEO' &&
          _videoController != null &&
          isUnlocked) {
        baseLayout = AspectRatio(
          aspectRatio: 16 / 9,
          child: _videoController!.value.isInitialized
              ? VideoPlayer(_videoController!)
              : const Center(child: DwellyOrbitingLoader()),
        );
      } else if (widget.rental.cardDisplayPreference == 'THREE_PICTURES' &&
          widget.rental.imageUrls.length >= 3) {
        baseLayout = AspectRatio(
          aspectRatio: 16 / 9,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: DwellyNetworkImage(
                  imageUrl: widget.rental.imageUrls[0],
                  thumbnailUrl: thumbAt(0),
                  fit: BoxFit.cover,
                  height: double.infinity,
                  memCacheWidth: twoThirdsCacheW,
                  memCacheHeight: fullCacheH,
                  errorWidget: _buildImageFallback(context),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Expanded(
                      child: DwellyNetworkImage(
                        imageUrl: widget.rental.imageUrls[1],
                        thumbnailUrl: thumbAt(1),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: oneThirdCacheW,
                        memCacheHeight: halfCacheH,
                        errorWidget: _buildImageFallback(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: DwellyNetworkImage(
                        imageUrl: widget.rental.imageUrls[2],
                        thumbnailUrl: thumbAt(2),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: oneThirdCacheW,
                        memCacheHeight: halfCacheH,
                        errorWidget: _buildImageFallback(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      } else if (widget.rental.cardDisplayPreference == 'DOUBLE_PICTURE' &&
          widget.rental.imageUrls.length >= 2) {
        baseLayout = AspectRatio(
          aspectRatio: 16 / 9,
          child: Row(
            children: [
              Expanded(
                child: DwellyNetworkImage(
                  imageUrl: widget.rental.imageUrls[0],
                  thumbnailUrl: thumbAt(0),
                  fit: BoxFit.cover,
                  height: double.infinity,
                  memCacheWidth: halfCacheW,
                  memCacheHeight: fullCacheH,
                  errorWidget: _buildImageFallback(context),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: DwellyNetworkImage(
                  imageUrl: widget.rental.imageUrls[1],
                  thumbnailUrl: thumbAt(1),
                  fit: BoxFit.cover,
                  height: double.infinity,
                  memCacheWidth: halfCacheW,
                  memCacheHeight: fullCacheH,
                  errorWidget: _buildImageFallback(context),
                ),
              ),
            ],
          ),
        );
      } else {
        baseLayout = AspectRatio(
          aspectRatio: 16 / 9,
          child: DwellyNetworkImage(
            imageUrl: widget.rental.imageUrls.isNotEmpty 
                ? widget.rental.imageUrls.first 
                : widget.rental.thumbnailUrls.first,
            thumbnailUrl: thumbAt(0),
            fit: BoxFit.cover,
            memCacheWidth: fullCacheW,
            memCacheHeight: fullCacheH,
            errorWidget: _buildImageFallback(context),
          ),
        );
      }
    } else {
      baseLayout = AspectRatio(
        aspectRatio: 16 / 9,
        child: DwellyNetworkImage(
          imageUrl: widget.rental.imageUrls.isNotEmpty 
              ? widget.rental.imageUrls.first 
              : widget.rental.thumbnailUrls.first,
          thumbnailUrl: thumbAt(0),
          fit: BoxFit.cover,
          memCacheWidth: fullCacheW,
          memCacheHeight: fullCacheH,
          errorWidget: _buildImageFallback(context),
        ),
      );
    }

    if (_compoundVideoController != null &&
        _compoundVideoController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [baseLayout, _buildCompoundVideoOverlay(context)],
        ),
      );
    }

    return baseLayout;
  }

  void _showOwnerPreview(BuildContext context, ThemeData theme) {
    final rental = widget.rental;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FullScreenImageAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                avatarUrl: rental.ownerAvatarUrl,
                fallbackWidget: Icon(
                  Icons.person,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                rental.ownerName ?? 'Owner',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (rental.ownerIsVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rental.isVerifiedAgent
                                ? 'Verified Agent'
                                : 'Verified',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (rental.ownerId != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserPublicProfilePage(userId: rental.ownerId!),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('View Full Profile'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specs =
        '${widget.rental.bedrooms} bed • ${widget.rental.bathrooms} bath • ${widget.rental.squareFeet} sqft${widget.rental.floor != null ? ' • Floor ${widget.rental.floor}' : ''}';

    final distanceText = _cachedDistanceText;

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: VisibilityDetector(
        key: Key(
          'rental-card-visibility-${widget.rental.id ?? widget.hashCode}',
        ),
        onVisibilityChanged: (info) {
          if (!mounted) return;
          if (info.visibleFraction > 0.3) {
            if (_compoundVideoController != null &&
                _compoundVideoController!.value.isInitialized &&
                !_compoundVideoController!.value.isPlaying) {
              _compoundVideoController!.play();
            }
            if (_videoController != null &&
                _videoController!.value.isInitialized &&
                !_videoController!.value.isPlaying) {
              _videoController!.play();
            }
          } else {
            if (_compoundVideoController != null &&
                _compoundVideoController!.value.isPlaying) {
              _compoundVideoController!.pause();
            }
            if (_videoController != null && _videoController!.value.isPlaying) {
              _videoController!.pause();
            }
          }
        },
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _buildMediaArea(context),
                  if (widget.isViewed)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.15),
                      ),
                    ),
                  if (widget.isViewed)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 12,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Viewed',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.isEffectivelySponsored)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.rental.sponsorshipType != null &&
                                      widget.rental.sponsorshipType != 'BOTH'
                                  ? 'Sponsored (${widget.rental.sponsorshipType})'
                                  : 'Sponsored',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FullScreenImageAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      avatarUrl: widget.rental.ownerAvatarUrl,
                      fallbackWidget: Icon(
                        Icons.person,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      onTap: () {
                        _showOwnerPreview(context, theme);
                      },
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
                                  widget.rental.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: widget.isViewed
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.rental.formattedPrice,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            specs,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.rental.displayLocation,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.rental.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.rental.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: _showHashtags ? 10 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (widget.rental.hashtags.isNotEmpty ||
                              widget.rental.description.length > 80) ...[
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showHashtags = !_showHashtags;
                                });
                              },
                              child: Text(
                                _showHashtags ? '...less' : '...more',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (_showHashtags &&
                              widget.rental.hashtags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: widget.rental.hashtags.map((tag) {
                                final displayTag = tag.startsWith('#')
                                    ? tag
                                    : '#$tag';
                                return ActionChip(
                                  label: Text(
                                    displayTag,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  backgroundColor: theme
                                      .colorScheme
                                      .primaryContainer
                                      .withOpacity(0.7),
                                  labelStyle: TextStyle(
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => HashtagSearchPage(
                                          hashtag: displayTag,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_isExactMatch)
                                      _buildStatusChip(
                                        context,
                                        'Exact area',
                                        Colors.blue,
                                      ),
                                    if (_isNearbyMatch)
                                      _buildStatusChip(
                                        context,
                                        'Nearby',
                                        Colors.green,
                                      ),
                                    if (widget.rental.ownerIsVerified)
                                      _buildStatusChip(
                                        context,
                                        widget.rental.isVerifiedAgent
                                            ? 'Verified Agent'
                                            : 'Verified',
                                        widget.rental.isVerifiedAgent
                                            ? const Color(0xFFFFB800)
                                            : Colors.blue,
                                      ),
                                    if (distanceText != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 2),
                                          Flexible(
                                            child: Text(
                                              distanceText,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
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
                              IconButton(
                                tooltip: widget.isSaved ? 'Unsave' : 'Save',
                                onPressed: widget.onToggleSave,
                                icon: Icon(
                                  widget.isSaved
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: widget.isSaved
                                      ? Colors.amber[700]
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Share listing',
                                onPressed: () => ShareListingSheet.show(
                                  context,
                                  widget.rental,
                                ),
                                icon: Icon(
                                  Icons.share_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Report listing',
                                onPressed: widget.onReport,
                                icon: Icon(
                                  Icons.flag_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageFallback(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.home_work_outlined,
        size: 38,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Report Bottom Sheet Widget
class _ReportBottomSheet extends StatefulWidget {
  final int rentalId;
  final String rentalTitle;

  const _ReportBottomSheet({required this.rentalId, required this.rentalTitle});

  @override
  State<_ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<_ReportBottomSheet> {
  final _descriptionController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;
  bool _hasAlreadyReported = false;
  bool _isCheckingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkReportStatus();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _checkReportStatus() async {
    try {
      final hasReported = await ReportService.hasReportedRental(
        widget.rentalId,
      );
      if (mounted) {
        setState(() {
          _hasAlreadyReported = hasReported;
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingStatus = false);
      }
    }
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a reason')));
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a description')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ReportService.createReport(
        rentalId: widget.rentalId,
        reason: _selectedReason!,
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report submitted successfully. We will review it shortly.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Failed to submit report.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: _isCheckingStatus
          ? const SizedBox(
              height: 200,
              child: Center(child: DwellyOrbitingLoader()),
            )
          : _buildReportForm(),
    );
  }

  Widget _buildReportForm() {
    final titleText = _hasAlreadyReported
        ? 'Add Additional Complaint'
        : 'Report Listing';
    final buttonText = _hasAlreadyReported
        ? 'Submit Additional Complaint'
        : 'Submit Report';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              const Icon(Icons.flag, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Report "${widget.rentalTitle}"',
            style: TextStyle(color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),

          // Reason selection
          const Text(
            'Why are you reporting this listing?',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          Column(
            children: ReportReason.defaultReasons
                .map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason.label),
                    value: reason.value,
                    groupValue: _selectedReason,
                    onChanged: (value) =>
                        setState(() => _selectedReason = value),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 16),

          // Description
          const Text(
            'Please provide details',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: _hasAlreadyReported
                  ? 'Add your new complaint here...'
                  : 'Describe the issue in detail...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: DwellyOrbitingLoader(),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
