import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/advertisement.dart';
import '../../../core/data/kenya_locations.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/navigation/app_tab_navigator.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/services/saved_rental_service.dart';
import '../../../core/services/user_preferences_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/widgets/app_launch_ad_screen.dart';
import '../../../core/widgets/ad_break_screen.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/top_notification_bell.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import '../../lost_id/presentation/found_id_scan_page.dart';
import '../../lost_id/presentation/search_lost_id_page.dart';
import '../../rentals/domain/rental_filters.dart' show UnitType, UnitTypeLabel;
import '../../marketplace/presentation/marketplace_shell_page.dart';
import '../../onboarding/widgets/onboarding_motion_step.dart';
import 'rental_detail_page.dart';

class ExplorePage extends StatefulWidget {
  final ValueChanged<bool>? onMarketplaceModeChanged;

  const ExplorePage({super.key, this.onMarketplaceModeChanged});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExploreSwipeUpHintSheet extends StatelessWidget {
  const _ExploreSwipeUpHintSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: OnboardingMotionScene(
                    type: OnboardingMotionType.scroll,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swipe_up_alt, size: 20),
                SizedBox(width: 6),
                Text(
                  'Swipe for more',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pull up to explore more rentals',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorePageState extends State<ExplorePage> {
  static const String _scrollHintSeenKey = 'explore_scroll_hint_seen_v1';

  // Mode toggle: false = Find Your Home, true = Marketplace
  bool _isMarketplaceMode = false;
  bool _isScrollHintCheckInProgress = false;
  bool _hasCheckedScrollHint = false;

  // Rentals and pagination
  List<Rental> _rentals = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _usingLocationAwareFeed = false;
  bool _usingConstituencyFeed = false;
  static const int _pageSize = 10;
  static const int _loadMoreSize = 10;

  // Search and filters
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
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

  // Ads
  AdService? _adService;
  List<int> _feedAdPositions = [];
  Map<int, Advertisement?> _feedAds = {}; // Position -> Ad
  Advertisement? _homeBannerAd;
  Advertisement? _homeFeedAd;
  Advertisement? _searchResultsAd;
  Advertisement? _locationFilterAd;
  Advertisement? _interstitialAd;
  int _rentalTapCount = 0;

  // Device location
  DeviceLocationResult? _deviceLocation;
  bool _isDetectingLocation = true;

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
  double _lastScrollOffset = 0;

  // Search autocomplete
  final _searchFocusNode = FocusNode();
  List<LocationSearchResult> _searchResults = [];
  Timer? _backendSearchDebounce;

  // Saved rental IDs (for bookmark state on cards)
  Set<int> _savedRentalIds = {};

  // Typewriter effect state
  Timer? _typewriterTimer;
  int _typewriterIndex = 0;
  String _typewriterText = '';
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
    _initPreferences();
    _loadSavedIds();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChange);
    ChatService.safetyVisibilityVersion.addListener(_onSafetyVisibilityChanged);
    _startTypewriterEffect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowScrollHint());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _backendSearchDebounce?.cancel();
    _typewriterTimer?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    ChatService.safetyVisibilityVersion.removeListener(
      _onSafetyVisibilityChanged,
    );
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSafetyVisibilityChanged() {
    if (!mounted || _isMarketplaceMode) return;
    unawaited(_loadRentals(refresh: true));
  }

  Future<void> _initPreferences() async {
    final results = await Future.wait([
      UserPreferencesService.getInstance(),
      AdService.getInstance(),
    ]);
    _prefsService = results[0] as UserPreferencesService;
    _adService = results[1] as AdService;

    // Load rentals immediately, then enrich with ads/location in background.
    _loadRentals();
    unawaited(_initAds());
    unawaited(_tryDetectLocation());
    unawaited(_showLaunchAdIfNeeded());
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
      setState(() => _feedAds = nextFeedAds);
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

  Future<void> _maybeShowScrollHint() async {
    if (_isMarketplaceMode ||
        _isScrollHintCheckInProgress ||
        _hasCheckedScrollHint) {
      return;
    }

    _isScrollHintCheckInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_scrollHintSeenKey) ?? false;
      _hasCheckedScrollHint = true;
      if (seen || !mounted || _isMarketplaceMode) {
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isDismissible: true,
        enableDrag: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const _ExploreSwipeUpHintSheet(),
      );

      await prefs.setBool(_scrollHintSeenKey, true);
    } catch (_) {
      // Fail open: do not block explore if hint fails.
      _hasCheckedScrollHint = true;
    } finally {
      _isScrollHintCheckInProgress = false;
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
      if (_searchController.text.isNotEmpty ||
          _isDetectingLocation ||
          _searchFocusNode.hasFocus)
        return;
      setState(() {
        final currentText = _placeholderTexts[_currentPlaceholderIndex];
        if (_isTypingAnim) {
          if (_typewriterIndex < currentText.length) {
            _typewriterText = currentText.substring(0, _typewriterIndex + 1);
            _typewriterIndex++;
          } else {
            _isTypingAnim = false;
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) setState(() {});
            });
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
      });
    });
  }

  Future<void> _toggleSaveRental(int rentalId) async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to save listings'),
          action: SnackBarAction(
            label: 'Login',
            onPressed: AppTabNavigator.openAccount,
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
          action: SnackBarAction(
            label: 'Login',
            onPressed: AppTabNavigator.openAccount,
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
    try {
      // First try cached location (instant)
      final cached = await DeviceLocationService.getCachedLocation();
      if (cached != null && cached.hasLocationData) {
        setState(() {
          _deviceLocation = cached;
          _isDetectingLocation = false;
        });
        unawaited(_refreshLocationAwareAds());
        if (!_useFYP && !_hasSearchContext && !_filters.hasFilters) {
          unawaited(_loadRentals(refresh: true));
        }
        return;
      }

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
          return;
        }
      }

      final result = await DeviceLocationService.getCurrentLocation();
      if (result.success && result.hasLocationData && mounted) {
        setState(() {
          _deviceLocation = result;
        });
        unawaited(_refreshLocationAwareAds());
        if (!_useFYP && !_hasSearchContext && !_filters.hasFilters) {
          unawaited(_loadRentals(refresh: true));
        }
      }
    } catch (_) {
      // Silently fail — just load all rentals
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  void _onScroll() {
    final offset = _scrollController.position.pixels;
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
    if (offset >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreRentals();
    }
  }

  /// Get FYP preferred areas — user's fypWards/fypNicknames first, then local prefs
  List<String> _getFypPreferredAreas() {
    final user = AuthService.currentUser;
    if (user != null && user.hasFypPreferences) {
      return [...user.fypWards, ...user.fypNicknames];
    }
    return _prefsService?.getPreferredAreas() ?? [];
  }

  Future<void> _loadRentals({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 0;
        _hasMore = true;
        _rentals.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      PaginatedRentals result;
      final hasConstituencyFilter =
          _filters.constituency != null && _filters.constituency!.isNotEmpty;
      _nearbyAreas = [];
      _borderNeighborAreas = [];
      _anchorWard = null;
      _anchorConstituency = null;
      _anchorCounty = null;
      _searchExhausted = false;
      _nextAction = null;

      if (_searchArea != null && _searchArea!.isNotEmpty) {
        // Use backend smart location search with filters
        final searchResult = await RentalService.smartLocationSearch(
          nickname: _searchArea,
          constituency: _filters.constituency,
          strictConstituency: hasConstituencyFilter,
          includeNearby: true,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          propertyType: _filters.propertyType,
          bedrooms: _filters.bedrooms,
          page: 0,
          size: _pageSize,
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
        result = searchResult.rentals;
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = false;
      } else if (_useFYP) {
        // FYP recommendations using user's fypWards/fypNicknames or local prefs
        final preferredAreas = _getFypPreferredAreas();
        final expandedBedrooms =
            _prefsService?.getExpandedBedroomPreferences() ?? [];
        final priceRange = _prefsService?.getPreferredPriceRange();

        result = await RentalService.getRecommendations(
          page: 0,
          size: _pageSize,
          preferredAreas: preferredAreas.isNotEmpty ? preferredAreas : null,
          expandedBedrooms: expandedBedrooms.isNotEmpty
              ? expandedBedrooms
              : null,
          minPrice: _filters.minPrice ?? priceRange?.min,
          maxPrice: _filters.maxPrice ?? priceRange?.max,
        );
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = false;
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
        result = searchResult.rentals;
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = true;
      } else if (_forceGlobalFeed) {
        result = await RentalService.getPaginated(
          page: 0,
          size: _pageSize,
          filters: _filters,
        );
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = false;
        _forceGlobalFeed = false;
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
            result = searchResult.rentals;
            _usingLocationAwareFeed = true;
            _usingConstituencyFeed = false;
          } else {
            result = await RentalService.getPaginated(
              page: 0,
              size: _pageSize,
              filters: _filters,
            );
            _usingLocationAwareFeed = false;
            _usingConstituencyFeed = false;
          }
        } catch (_) {
          result = await RentalService.getPaginated(
            page: 0,
            size: _pageSize,
            filters: _filters,
          );
          _usingLocationAwareFeed = false;
          _usingConstituencyFeed = false;
        }
      } else {
        // Regular paginated load with filters
        result = await RentalService.getPaginated(
          page: 0,
          size: _pageSize,
          filters: _filters,
        );
        _usingLocationAwareFeed = false;
        _usingConstituencyFeed = false;
      }

      setState(() {
        _rentals = result.rentals;
        _hasMore = result.hasMore;
        _currentPage = 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load rentals.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreRentals() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      PaginatedRentals result;
      final hasConstituencyFilter =
          _filters.constituency != null && _filters.constituency!.isNotEmpty;

      if (_searchArea != null && _searchArea!.isNotEmpty) {
        // Use backend smart location search with filters
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
        );
        _searchExhausted = searchResult.searchExhausted;
        _nextAction = searchResult.nextAction;
        result = searchResult.rentals;
      } else if (_usingConstituencyFeed && hasConstituencyFilter) {
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
        );
        _searchExhausted = searchResult.searchExhausted;
        _nextAction = searchResult.nextAction;
        result = searchResult.rentals;
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
        );
      } else if (_usingLocationAwareFeed &&
          _deviceLocation != null &&
          _deviceLocation!.hasLocationData) {
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
        );
        _searchExhausted = searchResult.searchExhausted;
        _nextAction = searchResult.nextAction;
        result = searchResult.rentals;
      } else {
        result = await RentalService.getPaginated(
          page: nextPage,
          size: _loadMoreSize,
          filters: _filters,
        );
      }

      setState(() {
        _rentals.addAll(result.rentals);
        _hasMore = result.hasMore;
        _currentPage = nextPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load more: $e')));
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
  }) {
    return RentalFilters(
      area: area,
      constituency: constituency,
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
      _filters = RentalFilters();
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
      if (result.type == LocationType.constituency) {
        _selectedConstituency = result.name;
      } else if (result.type == LocationType.ward &&
          result.constituency != null) {
        _selectedConstituency = result.constituency;
      }
      _filters = _filters.copyWith(constituency: _selectedConstituency);
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
    final colorScheme = Theme.of(context).colorScheme;

    // When marketplace mode is active, show the full independent marketplace mini-app
    if (_isMarketplaceMode) {
      return Scaffold(
        body: MarketplaceShellPage(
          onBackToHome: () {
            setState(() => _isMarketplaceMode = false);
            widget.onMarketplaceModeChanged?.call(false);
            unawaited(_maybeShowScrollHint());
          },
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TelegramTopBar(
                              title: 'Find Your Home',
                              subtitle: 'Rentals near you, faster to scan',
                              actions: [
                                const TopNotificationBell(),
                                IconButton(
                                  tooltip: 'Switch to Marketplace',
                                  onPressed: () {
                                    setState(() => _isMarketplaceMode = true);
                                    widget.onMarketplaceModeChanged?.call(true);
                                  },
                                  icon: const Icon(Icons.swap_horiz),
                                ),
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
                                      child: TextField(
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        decoration: InputDecoration(
                                          hintText: _isDetectingLocation
                                              ? 'Getting your location...'
                                              : _searchController.text.isEmpty
                                              ? (_searchFocusNode.hasFocus
                                                    ? 'Search ward, area or constituency...'
                                                    : (_typewriterText
                                                              .isNotEmpty
                                                          ? _typewriterText
                                                          : 'Search location...'))
                                              : null,
                                          prefixIcon: _isDetectingLocation
                                              ? const Padding(
                                                  padding: EdgeInsets.all(12),
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                )
                                              : IconButton(
                                                  icon: Icon(
                                                    Icons.search,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  ),
                                                  tooltip: 'Search locations',
                                                  onPressed: () =>
                                                      _searchFocusNode
                                                          .requestFocus(),
                                                ),
                                          suffixIcon:
                                              _searchController.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(Icons.clear),
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    setState(
                                                      () => _searchResults = [],
                                                    );
                                                    _onSearch('');
                                                  },
                                                )
                                              : IconButton(
                                                  icon: const Icon(
                                                    Icons.camera_alt_outlined,
                                                  ),
                                                  tooltip: 'Lost & Found ID',
                                                  onPressed:
                                                      _showIdOptionsDialog,
                                                ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withOpacity(0.55)
                                              : Colors.grey[100],
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12,
                                              ),
                                        ),
                                        onChanged: _onSearchTextChanged,
                                        onSubmitted: _onSearch,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Filter Button
                                    Container(
                                      decoration: BoxDecoration(
                                        color: _filters.hasFilters
                                            ? Theme.of(context).primaryColor
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.tune,
                                          color: _filters.hasFilters
                                              ? Colors.white
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                        onPressed: () => setState(() {
                                          _showFilters = !_showFilters;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // My Location Button
                                    Container(
                                      decoration: BoxDecoration(
                                        color:
                                            (_deviceLocation != null &&
                                                _searchArea ==
                                                    _deviceLocation!
                                                        .displayName)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: IconButton(
                                        onPressed: _isDetectingLocation
                                            ? null
                                            : () async {
                                                final result =
                                                    await DeviceLocationService.getCurrentLocation();
                                                if (result.success &&
                                                    result.hasLocationData &&
                                                    mounted) {
                                                  setState(() {
                                                    _deviceLocation = result;
                                                    _searchArea =
                                                        result.displayName;
                                                    _searchController.text =
                                                        result.displayName;
                                                    _useFYP = false;
                                                  });
                                                  _refreshLocationAwareAds();
                                                  _loadRentals(refresh: true);
                                                }
                                              },
                                        tooltip: 'Use my location',
                                        icon: _isDetectingLocation
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Icon(
                                                (_deviceLocation != null &&
                                                        _searchArea ==
                                                            _deviceLocation!
                                                                .displayName)
                                                    ? Icons.my_location
                                                    : Icons.location_searching,
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
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    ..._nearbyAreas
                                        .take(5)
                                        .map(
                                          (area) => Padding(
                                            padding: const EdgeInsets.only(
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
                                                _searchController.text =
                                                    LocationService.formatAreaName(
                                                      area,
                                                    );
                                                _onSearch(area);
                                              },
                                              backgroundColor: colorScheme
                                                  .secondaryContainer,
                                              visualDensity:
                                                  VisualDensity.compact,
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
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    ..._borderNeighborAreas
                                        .take(5)
                                        .map(
                                          (area) => Padding(
                                            padding: const EdgeInsets.only(
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
                                                _searchController.text =
                                                    LocationService.formatAreaName(
                                                      area,
                                                    );
                                                _onSearch(area);
                                              },
                                              backgroundColor:
                                                  colorScheme.tertiaryContainer,
                                              visualDensity:
                                                  VisualDensity.compact,
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
            // Location info banner + filter chips — also hide on scroll
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _isHeaderVisible
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Location info banner
                        if ((_searchArea != null && _searchArea!.isNotEmpty) ||
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
                                            _deviceLocation!.displayName)
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withOpacity(0.5)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    (_deviceLocation != null &&
                                            _searchArea ==
                                                _deviceLocation!.displayName)
                                        ? Icons.my_location
                                        : Icons.location_on,
                                    size: 16,
                                    color:
                                        (_deviceLocation != null &&
                                            _searchArea ==
                                                _deviceLocation!.displayName)
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (_activeAnchorLabel() != null &&
                                              _activeAnchorLabel()!
                                                  .trim()
                                                  .isNotEmpty)
                                          ? 'Showing results near ${_activeAnchorLabel()!}'
                                          : ((_deviceLocation != null &&
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
                                            fontWeight: FontWeight.w600,
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
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No more rentals in this radius.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (_anchorConstituency != null &&
                                          _anchorConstituency!.isNotEmpty)
                                        ActionChip(
                                          label: const Text(
                                            'Broaden to constituency',
                                          ),
                                          onPressed: _broadenToConstituency,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      if (_anchorCounty != null &&
                                          _anchorCounty!.isNotEmpty)
                                        ActionChip(
                                          label: const Text(
                                            'Broaden to county',
                                          ),
                                          onPressed: _broadenToCounty,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ActionChip(
                                        label: const Text('Show all Kenya'),
                                        onPressed: _showAllKenya,
                                        visualDensity: VisualDensity.compact,
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
            // Filter Panel OR Content
            if (_showFilters)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildFilterPanel(),
                ),
              )
            else ...[
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
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              _priceRange = RangeValues(_minPrice, _maxPrice);
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
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              _selectedBedrooms = null;
                              _filters = _filters.copyWith(bedrooms: null);
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
                          deleteIcon: const Icon(Icons.close, size: 16),
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
                          deleteIcon: const Icon(Icons.close, size: 16),
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
                                expandedBedrooms: _filters.expandedBedrooms,
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
              // Content
              Expanded(child: _buildContent()),
            ],
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _rentals.isEmpty) {
      return Center(
        child: Column(
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
      );
    }

    if (_rentals.isEmpty) {
      return Center(
        child: Column(
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
      );
    }

    final listView = RefreshIndicator(
      onRefresh: () => _loadRentals(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        itemCount: _getListItemCount(),
        itemBuilder: (context, index) {
          final itemInfo = _getItemAtIndex(index);

          if (itemInfo.isLoadingIndicator) {
            // Loading indicator at the bottom
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
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

          if (itemInfo.rental != null) {
            final rental = itemInfo.rental!;
            return _RentalCard(
              rental: rental,
              onTap: () => _onRentalTap(rental),
              searchArea: _searchArea,
              isSaved: rental.id != null && _savedRentalIds.contains(rental.id),
              onToggleSave: () {
                if (rental.id != null) _toggleSaveRental(rental.id!);
              },
              onReport: () => _showReportDialog(rental),
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

    for (int i = 0; i < _rentals.length; i++) {
      final rental = _rentals[i];
      final oneBasedPosition = i + 1;

      items.add(_ListItemInfo(rental: rental));

      // Context ads blend into feed and can re-appear later.
      if (contextAd != null &&
          (oneBasedPosition == 2 || oneBasedPosition % 12 == 0)) {
        _appendAdItem(items, contextAd, contextPlacement);
      }

      if (_canShowHomeFeedAd &&
          _homeFeedAd != null &&
          (oneBasedPosition == 1 || oneBasedPosition % 14 == 0)) {
        _appendAdItem(items, _homeFeedAd, AdPlacement.HOME_FEED.name);
      }

      if (validRentalFeedPositions.contains(oneBasedPosition)) {
        _appendAdItem(
          items,
          _feedAds[oneBasedPosition],
          AdPlacement.RENTAL_FEED.name,
        );
      }
    }

    if (_hasMore) {
      items.add(_ListItemInfo(isLoadingIndicator: true));
    }

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
}

/// Helper class to identify item type in list
class _ListItemInfo {
  final bool isAd;
  final bool isLoadingIndicator;
  final Advertisement? ad;
  final String? adPlacement;
  final Rental? rental;

  _ListItemInfo({
    this.isAd = false,
    this.isLoadingIndicator = false,
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
    return VisibilityDetector(
      key: Key(
        'feed-ad-visibility-${widget.placement}-${widget.ad.id}-${widget.listIndex}',
      ),
      onVisibilityChanged: _onVisibilityChanged,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () => _onTap(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ad image
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: widget.ad.imageUrl != null
                        ? Image.network(
                            widget.ad.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildPlaceholder();
                            },
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
              // Ad content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.ad.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sponsored',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    if (widget.ad.description != null &&
                        widget.ad.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.ad.description!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.business, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.ad.advertiserName,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildAdFeature(Icons.campaign_outlined, 'Promoted'),
                        const SizedBox(width: 16),
                        _buildAdFeature(
                          Icons.touch_app_outlined,
                          _getCtaLabel(),
                        ),
                      ],
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

  Widget _buildAdFeature(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _RentalCard extends StatelessWidget {
  final Rental rental;
  final VoidCallback onTap;
  final String? searchArea;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onReport;

  const _RentalCard({
    required this.rental,
    required this.onTap,
    this.searchArea,
    required this.isSaved,
    required this.onToggleSave,
    required this.onReport,
  });

  bool get _isExactMatch {
    if (searchArea == null) return false;
    return rental.city.toLowerCase() == searchArea!.toLowerCase();
  }

  bool get _isNearbyMatch {
    if (searchArea == null || _isExactMatch) return false;
    final nearbyAreas = LocationService.getNearbyAreas(searchArea!);
    return nearbyAreas.any(
      (area) => rental.city.toLowerCase().contains(area.toLowerCase()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specs =
        '${rental.bedrooms} bed ? ${rental.bathrooms} bath ? ${rental.squareFeet} sqft';

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rental.imageUrls.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  rental.imageUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildImageFallback(context),
                ),
              )
            else
              _buildImageFallback(context),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rental.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        rental.formattedPrice,
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
                    '${rental.city}, ${rental.state}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (_isExactMatch)
                            _buildStatusChip(
                              context,
                              'Exact area',
                              Colors.blue,
                            ),
                          if (_isNearbyMatch)
                            _buildStatusChip(context, 'Nearby', Colors.green),
                          if (rental.ownerIsVerified)
                            _buildStatusChip(
                              context,
                              rental.isVerifiedAgent
                                  ? 'Verified Agent'
                                  : 'Verified',
                              rental.isVerifiedAgent
                                  ? const Color(0xFFFFB800)
                                  : Colors.blue,
                            ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: isSaved ? 'Unsave' : 'Save',
                        onPressed: onToggleSave,
                        icon: Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: isSaved
                              ? Colors.amber[700]
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Report listing',
                        onPressed: onReport,
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
    );
  }

  Widget _buildImageFallback(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.home_work_outlined,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
              child: Center(child: CircularProgressIndicator()),
            )
          : _hasAlreadyReported
          ? _buildAlreadyReportedView()
          : _buildReportForm(),
    );
  }

  Widget _buildAlreadyReportedView() {
    return SizedBox(
      height: 200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'You have already reported this listing',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Our team is reviewing your report',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportForm() {
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
              const Text(
                'Report Listing',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              hintText: 'Describe the issue in detail...',
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Report',
                      style: TextStyle(
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
