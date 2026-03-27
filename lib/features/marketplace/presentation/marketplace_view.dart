import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/kenya_locations.dart';
import '../../../core/navigation/app_tab_navigator.dart';
import '../../../core/models/advertisement.dart';
import '../../../core/models/marketplace_commerce.dart';
import '../../../core/models/marketplace_product.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/theme/marketplace_theme.dart';
import '../../../core/widgets/feed_ad_widget.dart';
import 'marketplace_cart_page.dart';
import 'post_product_page.dart';
import 'product_detail_page.dart';
import 'widgets/product_card.dart';

enum MarketplaceViewMode { home, search }

class MarketplaceView extends StatefulWidget {
  final String? defaultCounty;
  final String? defaultConstituency;
  final String? defaultWard;
  final MarketplaceViewMode mode;

  const MarketplaceView({
    super.key,
    this.defaultCounty,
    this.defaultConstituency,
    this.defaultWard,
    this.mode = MarketplaceViewMode.home,
  });

  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView>
    with WidgetsBindingObserver {
  static const int _pageSize = 6;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _rotationTick = ValueNotifier<int>(0);
  Timer? _searchDebounce;
  Timer? _rotationTimer;
  Timer? _loadWatchdogTimer;
  Timer? _smartRefreshTimer;
  int _activeLoadRequestId = 0;
  static const Duration _firstLoadTimeout = Duration(seconds: 8);
  static const Duration _firstLoadRetryTimeout = Duration(seconds: 5);
  static const Duration _defaultLoadTimeout = Duration(seconds: 8);
  static const Duration _loadWatchdogTimeout = Duration(seconds: 15);

  final List<MarketplaceProduct> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String? _error;
  String? _rankingVersion;
  String? _viewerLocationUsed;
  bool _restrictedFilterApplied = false;
  String _sort = 'SMART';
  String _preferredLoadMode = 'SMART';
  String? _servedMode;
  List<String> _warnings = const [];
  MarketplaceStorefrontPayload? _storefront;
  final Set<int> _cartPendingProductIds = <int>{};
  bool _showSeedFallback = false;
  AdService? _adService;
  Advertisement? _marketplaceTopAd;
  List<Advertisement> _marketplaceFeedAds = const [];
  Set<int> _marketplaceFeedAdPositions = const {};

  String? _selectedCategory;
  String? _selectedCondition;
  String? _selectedCounty;
  String? _selectedConstituency;
  String? _selectedWard;
  bool _savedOnly = false;
  bool _isForeground = true;
  bool _secretDealsRevealed = false;

  List<String> _categories = const [
    'ELECTRONICS',
    'PHONES',
    'FASHION',
    'HOME',
    'BEAUTY',
    'BABY',
    'SPORTS',
    'AUTO',
    'SERVICES',
    'OTHER',
  ];

  static final List<MarketplaceProduct> _seedProducts = [
    const MarketplaceProduct(
      id: -1,
      title: 'Samsung Galaxy S24 Ultra',
      description:
          'Brand new Samsung Galaxy S24 Ultra, 256GB, Titanium Black. Sealed in box with warranty.',
      price: 165000,
      category: 'PHONES',
      condition: 'NEW',
      county: 'Nairobi',
      constituency: 'Westlands',
      ward: 'Parklands',
      imageUrls: [],
      sellerName: 'TechHub KE',
      sellerVerified: true,
      viewCount: 342,
      likeCount: 89,
      saveCount: 45,
      sellerMarketplaceBadge: true,
    ),
    const MarketplaceProduct(
      id: -2,
      title: 'Modern L-Shaped Sofa',
      description:
          'Elegant grey L-shaped sofa, barely used. Perfect for living room. Comes with throw pillows.',
      price: 45000,
      category: 'HOME',
      condition: 'LIKE_NEW',
      county: 'Nairobi',
      constituency: 'Langata',
      ward: 'Karen',
      imageUrls: [],
      sellerName: 'FurnishKE',
      viewCount: 128,
      likeCount: 34,
      saveCount: 22,
    ),
    const MarketplaceProduct(
      id: -3,
      title: 'Nike Air Jordan 1 Retro',
      description:
          'Original Nike Air Jordan 1 Retro High OG. Size 43. Brand new with tags.',
      price: 18500,
      category: 'FASHION',
      condition: 'NEW',
      county: 'Nairobi',
      constituency: 'Starehe',
      ward: 'Nairobi Central',
      imageUrls: [],
      sellerName: 'SneakerSpot',
      sellerVerified: true,
      viewCount: 256,
      likeCount: 67,
      saveCount: 31,
      sellerMarketplaceBadge: true,
    ),
    const MarketplaceProduct(
      id: -4,
      title: 'HP Laptop EliteBook 840',
      description:
          'HP EliteBook 840 G8, Core i7, 16GB RAM, 512GB SSD. Great for business and everyday use.',
      price: 55000,
      category: 'ELECTRONICS',
      condition: 'USED_GOOD',
      county: 'Mombasa',
      constituency: 'Mvita',
      ward: 'Mji Wa Kale',
      imageUrls: [],
      sellerName: 'CompWorld',
      viewCount: 198,
      likeCount: 42,
      saveCount: 18,
    ),
    const MarketplaceProduct(
      id: -5,
      title: 'Baby Stroller - Chicco',
      description:
          'Chicco baby stroller, foldable, lightweight. Used for 6 months only. In perfect condition.',
      price: 12000,
      category: 'BABY',
      condition: 'LIKE_NEW',
      county: 'Nairobi',
      constituency: 'Dagoretti North',
      ward: 'Kilimani',
      imageUrls: [],
      sellerName: 'MamaCare',
      viewCount: 87,
      likeCount: 23,
      saveCount: 15,
    ),
    const MarketplaceProduct(
      id: -6,
      title: 'Toyota Vitz 2015',
      description:
          '2015 Toyota Vitz, 1300cc, automatic. Low mileage, well maintained. Clean interior.',
      price: 750000,
      category: 'AUTO',
      condition: 'USED_GOOD',
      county: 'Nairobi',
      constituency: 'Embakasi East',
      ward: 'Utawala',
      imageUrls: [],
      sellerName: 'AutoDeals KE',
      sellerVerified: true,
      viewCount: 543,
      likeCount: 112,
      saveCount: 78,
      sellerMarketplaceBadge: true,
    ),
    const MarketplaceProduct(
      id: -7,
      title: 'Professional Hair Dryer',
      description:
          'Dyson Supersonic hair dryer. Barely used, comes with all attachments and original box.',
      price: 8500,
      category: 'BEAUTY',
      condition: 'LIKE_NEW',
      county: 'Nairobi',
      constituency: 'Westlands',
      ward: 'Kitisuru',
      imageUrls: [],
      sellerName: 'GlamStore',
      viewCount: 65,
      likeCount: 19,
      saveCount: 11,
    ),
    const MarketplaceProduct(
      id: -8,
      title: 'Football Boots - Adidas',
      description:
          'Adidas Predator Edge football boots. Size 42. Used twice on grass pitch.',
      price: 7500,
      category: 'SPORTS',
      condition: 'LIKE_NEW',
      county: 'Kisumu',
      constituency: 'Kisumu Central',
      ward: 'Kondele',
      imageUrls: [],
      sellerName: 'SportZone',
      viewCount: 44,
      likeCount: 12,
      saveCount: 8,
    ),
    const MarketplaceProduct(
      id: -9,
      title: 'Plumbing Services',
      description:
          'Professional plumbing services - installations, repairs, and maintenance. Available 24/7.',
      price: 2500,
      category: 'SERVICES',
      condition: 'NEW',
      county: 'Nairobi',
      constituency: 'Roysambu',
      ward: 'Zimmerman',
      imageUrls: [],
      sellerName: 'FixIt Pro',
      sellerVerified: true,
      viewCount: 320,
      likeCount: 56,
      saveCount: 40,
      sellerMarketplaceBadge: true,
    ),
    const MarketplaceProduct(
      id: -10,
      title: 'iPhone 15 Pro Max 256GB',
      description:
          'Apple iPhone 15 Pro Max, Natural Titanium, 256GB. Comes with original accessories.',
      price: 195000,
      category: 'PHONES',
      condition: 'NEW',
      county: 'Nairobi',
      constituency: 'Starehe',
      ward: 'Nairobi Central',
      imageUrls: [],
      sellerName: 'iStore KE',
      sellerVerified: true,
      viewCount: 678,
      likeCount: 145,
      saveCount: 92,
      sellerMarketplaceBadge: true,
    ),
  ];

  static const List<String> _homeQuickFilters = [
    'Under 2K',
    'Luxury',
    'Streetwear',
    'Near Me',
    'Same-day',
  ];

  static const List<String> _moodFilters = [
    'Feeling Bold 😈',
    'Chill & Cozy 🧸',
    'Luxury Mode 💎',
  ];

  static const List<String> _smartSearchSuggestions = [
    'People are searching for: Air fryer',
    'Trending now: iPhone 15 Pro',
    'Voice search: Tap mic and speak',
    'Image search: Upload photo to find matches',
  ];

  static const List<String> _livePurchaseTicker = [
    'Brian from Nairobi just bought Nike Air Jordan 1',
    'Amina from Mombasa just ordered HP EliteBook 840',
    'Kelvin from Kisumu just bought Samsung S24 Ultra',
  ];

  static const List<String> _communityReviews = [
    '“Exactly as described. Fast delivery!” — Cynthia, Nairobi',
    '“Quality is premium. Seller was responsive.” — David, Eldoret',
    '“Styled by real people vibe is 🔥” — Mercy, Nakuru',
  ];

  static const List<String> _influencerPicks = [
    'Njeri Styles: Streetwear Starter Pack',
    'Tech with Ian: Creator Desk Essentials',
    'Home by Asha: Cozy Apartment Setup',
  ];

  List<String> _conditions = const [
    'NEW',
    'LIKE_NEW',
    'USED_GOOD',
    'USED_FAIR',
  ];
  List<String> _counties = List<String>.from(KenyaLocations.counties);
  Map<String, List<String>> _constituenciesByCounty =
      Map<String, List<String>>.fromEntries(
        KenyaLocations.constituenciesByCounty.entries.map(
          (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
        ),
      );
  Map<String, List<String>> _wardsByConstituency =
      Map<String, List<String>>.fromEntries(
        KenyaLocations.wardsByConstituency.entries.map(
          (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
        ),
      );

  static const List<String> _sortModes = [
    'SMART',
    'NEWEST',
    'TOP_RATED',
    'MOST_LIKED',
    'PRICE_ASC',
    'PRICE_DESC',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Validate default location values against available lists
    _selectedCounty = widget.defaultCounty;
    if (_selectedCounty != null) {
      final validConstituencies =
          _constituenciesByCounty[_selectedCounty] ?? const <String>[];
      _selectedConstituency =
          (widget.defaultConstituency != null &&
              validConstituencies.contains(widget.defaultConstituency))
          ? widget.defaultConstituency
          : null;
    }
    if (_selectedConstituency != null) {
      final validWards =
          _wardsByConstituency[_selectedConstituency] ?? const <String>[];
      _selectedWard =
          (widget.defaultWard != null &&
              validWards.contains(widget.defaultWard))
          ? widget.defaultWard
          : null;
    }
    _scrollController.addListener(_onScroll);
    _startRotationTicker();
    _initAdService();
    _bootstrapInitialLoad();
    if (widget.mode == MarketplaceViewMode.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _rotationTimer?.cancel();
    _loadWatchdogTimer?.cancel();
    _smartRefreshTimer?.cancel();
    _rotationTick.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_isForeground == active) return;
    _isForeground = active;
    if (active) {
      _startRotationTicker();
    } else {
      _rotationTimer?.cancel();
      _rotationTimer = null;
    }
  }

  void _startRotationTicker() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!_isForeground) return;
      _rotationTick.value = _rotationTick.value + 1;
    });
  }

  Future<void> _initAdService() async {
    try {
      final service = await AdService.getInstance();
      if (!mounted) return;
      setState(() => _adService = service);
    } catch (_) {
      // Keep ads optional in marketplace.
    }
  }

  Future<void> _bootstrapInitialLoad() async {
    final cachedCounty = _selectedCounty ?? widget.defaultCounty;
    try {
      final bootstrap = await MarketplaceService.getBootstrap(
        viewerCounty: cachedCounty,
      );
      if (!mounted) return;
      _applyBootstrap(bootstrap);
      if (_storefront == null) {
        unawaited(_loadStorefront(cachedCounty));
      }
      // Only schedule SMART refresh if bootstrap returned no products.
      if (_products.isEmpty) {
        _scheduleSmartRefresh();
      }
      _deferAdLoad();
    } catch (e) {
      if (!mounted) return;
      // Bootstrap failed; fall back to a single direct products request.
      // Don't retry — the user already waited for the bootstrap timeout.
      await _loadProducts(refresh: true, loadMode: 'FAST', allowRetry: false);
      unawaited(_loadStorefront(cachedCounty));
    }
  }

  void _applyBootstrap(MarketplaceBootstrapPayload payload) {
    final mergedWarnings = <String>[
      ...payload.warnings,
      ...payload.home.warnings,
    ];
    setState(() {
      _products
        ..clear()
        ..addAll(payload.home.products);
      _hasMore = payload.home.hasMore;
      _currentPage = payload.home.currentPage;
      _rankingVersion = payload.home.rankingVersion;
      _viewerLocationUsed = payload.home.viewerLocationUsed;
      _restrictedFilterApplied = payload.home.restrictedFilterApplied;
      _error = null;
      _isLoading = false;
      _preferredLoadMode = 'SMART';
      _servedMode = payload.home.servedMode;
      _warnings = mergedWarnings;
      _showSeedFallback =
          payload.home.products.isEmpty && _shouldUseSeedFallback();
      _storefront = payload.storefront;

      if (payload.filters.categories.isNotEmpty) {
        _categories = payload.filters.categories;
      }
      if (payload.filters.conditions.isNotEmpty) {
        _conditions = payload.filters.conditions;
      }
      if (payload.filters.counties.isNotEmpty) {
        _counties = payload.filters.counties;
      }
      if (payload.filters.constituenciesByCounty.isNotEmpty) {
        _constituenciesByCounty = payload.filters.constituenciesByCounty;
      }
      if (payload.filters.wardsByConstituency.isNotEmpty) {
        _wardsByConstituency = payload.filters.wardsByConstituency;
      }
    });
  }

  Future<void> _loadStorefront(String? viewerCounty) async {
    try {
      final storefront = await MarketplaceService.getStorefront(
        viewerCounty: viewerCounty,
        requestTimeout: const Duration(milliseconds: 4200),
      );
      if (!mounted) return;
      setState(() => _storefront = storefront);
    } catch (_) {
      // Fail open: storefront enhancements are optional.
    }
  }

  void _scheduleSmartRefresh() {
    _smartRefreshTimer?.cancel();
    _smartRefreshTimer = Timer(
      const Duration(milliseconds: 800),
      () => _loadProducts(refresh: true, loadMode: 'SMART', allowRetry: false),
    );
  }

  void _deferAdLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _products.isEmpty) return;
      unawaited(_loadMarketplaceAdSafely());
    });
  }

  Future<void> _loadMarketplaceAd() async {
    final service = _adService;
    if (service == null || _savedOnly) {
      if (!mounted) return;
      setState(() {
        _marketplaceTopAd = null;
        _marketplaceFeedAds = const [];
        _marketplaceFeedAdPositions = const {};
      });
      return;
    }

    final query = _searchController.text.trim();
    final isSearch = query.isNotEmpty;
    final config = await service.getDisplayConfig();

    if (isSearch && !config.marketplaceSearchAdEnabled) {
      if (!mounted) return;
      setState(() {
        _marketplaceTopAd = null;
        _marketplaceFeedAds = const [];
        _marketplaceFeedAdPositions = const {};
      });
      return;
    }

    if (!isSearch && !config.marketplaceFeedAdEnabled) {
      if (!mounted) return;
      setState(() {
        _marketplaceTopAd = null;
        _marketplaceFeedAds = const [];
        _marketplaceFeedAdPositions = const {};
      });
      return;
    }

    final placement = isSearch
        ? AdPlacement.MARKETPLACE_SEARCH
        : AdPlacement.MARKETPLACE_FEED;
    final targeted = await service.getTargetedAd(
      placement,
      county: _selectedCounty,
      constituency: _selectedConstituency,
    );
    final fetchedAds = await service.getAdsForPlacement(placement);
    final mergedAds = <Advertisement>[
      if (targeted != null) targeted,
      ...fetchedAds.where((ad) => ad.id != targeted?.id),
    ];

    if (!mounted) return;
    setState(() {
      _marketplaceTopAd = isSearch
          ? (mergedAds.isEmpty ? null : mergedAds.first)
          : null;
      _marketplaceFeedAds = isSearch ? const [] : mergedAds;
      _marketplaceFeedAdPositions = isSearch
          ? const {}
          : config.marketplaceFeedPositions
                .where((position) => position > 0)
                .toSet();
    });
  }

  Future<void> _loadMarketplaceAdSafely() async {
    try {
      await _loadMarketplaceAd();
    } catch (_) {
      // Ads are optional. Never block marketplace product rendering.
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadProducts({
    bool refresh = false,
    String? loadMode,
    bool allowRetry = true,
  }) async {
    final requestId = ++_activeLoadRequestId;
    final hadVisibleProducts = _products.isNotEmpty;
    final targetPage = refresh ? 0 : _currentPage;
    final effectiveLoadMode = loadMode ?? _preferredLoadMode;
    if (refresh) {
      setState(() {
        _isLoading = !hadVisibleProducts;
        _error = null;
        _currentPage = 0;
        _hasMore = true;
        _showSeedFallback = false;
      });
    } else {
      setState(() => _error = null);
    }
    _startLoadWatchdog(requestId);

    try {
      final shouldRetry =
          allowRetry &&
          refresh &&
          !hadVisibleProducts &&
          targetPage == 0 &&
          !_savedOnly;
      final result =
          await _requestProductsPage(
            page: targetPage,
            timeout: _firstLoadTimeout,
            loadMode: effectiveLoadMode,
          ).catchError((error) async {
            if (!shouldRetry) {
              throw error;
            }
            await Future<void>.delayed(const Duration(milliseconds: 260));
            return _requestProductsPage(
              page: targetPage,
              timeout: _firstLoadRetryTimeout,
              loadMode: effectiveLoadMode,
            );
          });

      if (!mounted || requestId != _activeLoadRequestId) return;
      setState(() {
        if (refresh) {
          _products
            ..clear()
            ..addAll(result.products);
        } else {
          _products.addAll(result.products);
        }
        _hasMore = result.hasMore;
        _isLoading = false;
        _rankingVersion = result.rankingVersion;
        _viewerLocationUsed = result.viewerLocationUsed;
        _restrictedFilterApplied = result.restrictedFilterApplied;
        _servedMode = result.servedMode;
        _warnings = result.warnings;
        _error = null;
        _showSeedFallback =
            refresh && result.products.isEmpty && _shouldUseSeedFallback();
      });
      _deferAdLoad();
    } catch (e) {
      if (!mounted || requestId != _activeLoadRequestId) return;
      setState(() {
        _isLoading = false;
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load products. Please try again.',
        );
        _showSeedFallback = !_savedOnly && _products.isEmpty;
      });
    } finally {
      if (requestId == _activeLoadRequestId) {
        _loadWatchdogTimer?.cancel();
        _loadWatchdogTimer = null;
        if (mounted && _isLoading) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<PaginatedMarketplaceProducts> _requestProductsPage({
    required int page,
    required Duration timeout,
    required String loadMode,
  }) {
    if (_savedOnly) {
      return MarketplaceService.getSavedProducts(
        page: page,
        size: _pageSize,
        requestTimeout: timeout,
      );
    }
    return MarketplaceService.getProducts(
      page: page,
      size: _pageSize,
      query: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      category: _selectedCategory,
      county: _selectedCounty,
      constituency: _selectedConstituency,
      ward: _selectedWard,
      condition: _selectedCondition,
      sort: _sort,
      loadMode: loadMode,
      viewerCounty: _selectedCounty,
      requestTimeout: timeout,
    );
  }

  bool _shouldUseSeedFallback() {
    return !_savedOnly && _searchController.text.trim().isEmpty;
  }

  List<MarketplaceProduct> _filteredSeedProducts() {
    return _seedProducts
        .where((product) {
          if (_selectedCategory != null &&
              product.category != _selectedCategory) {
            return false;
          }
          if (_selectedCondition != null &&
              product.condition != _selectedCondition) {
            return false;
          }
          if (_selectedCounty != null &&
              product.county.toLowerCase() != _selectedCounty!.toLowerCase()) {
            return false;
          }
          if (_selectedConstituency != null &&
              product.constituency.toLowerCase() !=
                  _selectedConstituency!.toLowerCase()) {
            return false;
          }
          if (_selectedWard != null &&
              product.ward.toLowerCase() != _selectedWard!.toLowerCase()) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _startLoadWatchdog(int requestId) {
    _loadWatchdogTimer?.cancel();
    _loadWatchdogTimer = Timer(_loadWatchdogTimeout, () {
      if (!mounted || requestId != _activeLoadRequestId || !_isLoading) return;
      setState(() {
        _isLoading = false;
        _error =
            'Could not reach the server. Check your connection and try again.';
      });
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      _currentPage += 1;
      final result = await _requestProductsPage(
        page: _currentPage,
        timeout: _defaultLoadTimeout,
        loadMode: _preferredLoadMode,
      );

      if (!mounted) return;
      setState(() {
        _products.addAll(result.products);
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load more products. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _refresh() => _loadProducts(refresh: true);

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadProducts(refresh: true);
    });
  }

  Future<void> _openPostProduct() async {
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to post products');
      return;
    }

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PostProductPage()),
    );
    if (created == true && mounted) {
      _refresh();
    }
  }

  Future<void> _openProduct(MarketplaceProduct product) async {
    if (product.id == null) return;
    // Seed products have negative IDs — show a snack instead
    if (product.id! < 0) {
      _showSnack('This is a sample listing. Post your own product!');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(productId: product.id!),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _toggleSave(MarketplaceProduct product) async {
    if (product.id == null) return;
    if (product.id! < 0) {
      _showSignInSnack('Sign in and post products to save them');
      return;
    }
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to save products');
      return;
    }

    try {
      if (product.savedByViewer) {
        await MarketplaceService.unsaveProduct(product.id!);
      } else {
        await MarketplaceService.saveProduct(product.id!);
      }
      if (!mounted) return;
      setState(() {
        final index = _products.indexWhere((p) => p.id == product.id);
        if (index >= 0) {
          _products[index] = product.copyWith(
            savedByViewer: !product.savedByViewer,
            saveCount: product.savedByViewer
                ? (product.saveCount - 1).clamp(0, 1 << 30)
                : product.saveCount + 1,
          );
        }
      });
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to update saved products. Please try again.',
      );
    }
  }

  Future<void> _toggleLike(MarketplaceProduct product) async {
    if (product.id == null) return;
    if (product.id! < 0) {
      _showSignInSnack('Sign in and post products to like them');
      return;
    }
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to like products');
      return;
    }

    try {
      final updated = product.likedByViewer
          ? await MarketplaceService.unlikeProduct(product.id!)
          : await MarketplaceService.likeProduct(product.id!);
      if (!mounted) return;
      setState(() {
        final index = _products.indexWhere((p) => p.id == product.id);
        if (index >= 0) {
          _products[index] = updated.copyWith(
            savedByViewer: _products[index].savedByViewer,
          );
        }
      });
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to update likes. Please try again.',
      );
    }
  }

  Future<void> _openCartPage() async {
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to access your cart');
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MarketplaceCartPage()));
  }

  Future<void> _addToCart(MarketplaceProduct product) async {
    final productId = product.id;
    if (productId == null || productId < 0) {
      _showSnack('This is a sample product and cannot be purchased.');
      return;
    }
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to add products to cart');
      return;
    }
    if (_cartPendingProductIds.contains(productId)) return;

    setState(() => _cartPendingProductIds.add(productId));
    try {
      final cart = await MarketplaceService.addCartItem(productId);
      if (!mounted) return;
      _showSnack(
        'Added to cart (${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'})',
      );
    } catch (e) {
      _showError(e, fallbackMessage: 'Failed to add this product to cart.');
    } finally {
      if (mounted) {
        setState(() => _cartPendingProductIds.remove(productId));
      }
    }
  }

  void _showError(Object error, {required String fallbackMessage}) {
    if (!mounted || isSilentError(error)) return;
    showErrorSnackBar(context, error, fallbackMessage: fallbackMessage);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSignInSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: AppTabNavigator.openAccount,
        ),
      ),
    );
  }

  List<_MarketplaceGridEntry> _buildGridEntries() {
    // Use seed data when no products loaded from API
    final displayProducts =
        _showSeedFallback && _products.isEmpty && !_isLoading && !_savedOnly
        ? (() {
            final filteredSeeds = _filteredSeedProducts();
            return filteredSeeds.isEmpty ? _seedProducts : filteredSeeds;
          })()
        : _products;

    if (_savedOnly ||
        _marketplaceFeedAds.isEmpty ||
        _marketplaceFeedAdPositions.isEmpty) {
      return displayProducts.map(_MarketplaceGridEntry.product).toList();
    }

    final entries = <_MarketplaceGridEntry>[];
    var adCursor = 0;
    for (final product in displayProducts) {
      final nextIndex = entries.length + 1;
      if (_marketplaceFeedAdPositions.contains(nextIndex)) {
        final ad = _marketplaceFeedAds[adCursor % _marketplaceFeedAds.length];
        entries.add(_MarketplaceGridEntry.ad(ad));
        adCursor += 1;
      }
      entries.add(_MarketplaceGridEntry.product(product));
    }

    return entries;
  }

  Widget _buildGridAdCard(Advertisement ad) {
    final adService = _adService;
    if (adService == null) {
      return const SizedBox.shrink();
    }
    return FeedAdWidget(
      ad: ad,
      adService: adService,
      height: 210,
      margin: EdgeInsets.zero,
    );
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != null) count++;
    if (_selectedCondition != null) count++;
    if (_selectedCounty != null) count++;
    if (_selectedConstituency != null) count++;
    if (_selectedWard != null) count++;
    if (_sort != 'SMART') count++;
    if (_savedOnly) count++;
    return count;
  }

  Future<void> _openFiltersSheet() async {
    String? category = _selectedCategory;
    String? condition = _selectedCondition;
    String? county = _selectedCounty;
    String? constituency = _selectedConstituency;
    String? ward = _selectedWard;
    String sort = _sort;
    bool savedOnly = _savedOnly;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final constituencies = county != null
                ? (_constituenciesByCounty[county] ?? const <String>[])
                : const <String>[];
            final wards = constituency != null
                ? (_wardsByConstituency[constituency] ?? const <String>[])
                : const <String>[];

            if (constituency != null &&
                !constituencies.contains(constituency)) {
              constituency = null;
              ward = null;
            }
            if (ward != null && !wards.contains(ward)) {
              ward = null;
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filter Marketplace',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                category = null;
                                condition = null;
                                county = null;
                                constituency = null;
                                ward = null;
                                sort = 'SMART';
                                savedOnly = false;
                              });
                            },
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: savedOnly,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Saved only'),
                        subtitle: const Text(
                          'Show your bookmarked products only',
                        ),
                        onChanged: (value) =>
                            setSheetState(() => savedOnly = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('sort-$sort'),
                        initialValue: sort,
                        isExpanded: true,
                        items: _sortModes
                            .map(
                              (mode) => DropdownMenuItem<String>(
                                value: mode,
                                child: Text(mode.replaceAll('_', ' ')),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setSheetState(() => sort = value ?? 'SMART'),
                        decoration: const InputDecoration(
                          labelText: 'Sort',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Category',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: category == null,
                            onSelected: (_) =>
                                setSheetState(() => category = null),
                          ),
                          ..._categories.map((cat) {
                            final selected = category == cat;
                            return ChoiceChip(
                              label: Text(
                                cat[0] + cat.substring(1).toLowerCase(),
                              ),
                              selected: selected,
                              onSelected: (_) => setSheetState(
                                () => category = selected ? null : cat,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: ValueKey<String>(
                          'condition-${condition ?? 'all'}',
                        ),
                        initialValue: condition,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All conditions'),
                          ),
                          ..._conditions.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(item),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => condition = value),
                        decoration: const InputDecoration(
                          labelText: 'Condition',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: ValueKey<String>('county-${county ?? 'all'}'),
                        initialValue: county,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All counties'),
                          ),
                          ..._counties.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() {
                          county = value;
                          constituency = null;
                          ward = null;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'County',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: ValueKey<String>(
                          'constituency-${constituency ?? 'all'}',
                        ),
                        initialValue: constituency,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All constituencies'),
                          ),
                          ...constituencies.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() {
                          constituency = value;
                          ward = null;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Constituency',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: ValueKey<String>('ward-${ward ?? 'all'}'),
                        initialValue: ward,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All wards'),
                          ),
                          ...wards.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() => ward = value),
                        decoration: const InputDecoration(
                          labelText: 'Ward',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            if (savedOnly && !AuthService.isLoggedIn) {
                              _showSignInSnack(
                                'Sign in to view saved products',
                              );
                              return;
                            }
                            setState(() {
                              _selectedCategory = category;
                              _selectedCondition = condition;
                              _selectedCounty = county;
                              _selectedConstituency = constituency;
                              _selectedWard = ward;
                              _sort = sort;
                              _savedOnly = savedOnly;
                            });
                            await _refresh();
                          },
                          child: const Text('Apply filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingSkeletonGrid(
    Color baseColor, {
    int columns = 2,
    double aspectRatio = 0.72,
  }) {
    final highlightColor = baseColor.withValues(alpha: 0.65);
    return GridView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: aspectRatio,
      ),
      itemCount: 6,
      itemBuilder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: baseColor.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      color: highlightColor,
                    ),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 90, color: baseColor),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 120, color: highlightColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final text = _savedOnly
        ? 'No saved products yet.'
        : 'No products match your current filters.';
    final actionText = _savedOnly ? 'Browse products' : 'Clear filters';

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 340,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 46,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try changing category, location, or sort options.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () async {
                    if (_savedOnly) {
                      setState(() => _savedOnly = false);
                    } else {
                      setState(() {
                        _selectedCategory = null;
                        _selectedCondition = null;
                        _selectedCounty = null;
                        _selectedConstituency = null;
                        _selectedWard = null;
                        _sort = 'SMART';
                      });
                    }
                    await _refresh();
                  },
                  child: Text(actionText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorefrontHero(ColorScheme colorScheme) {
    final heroTitle =
        _storefront?.heroTitle ?? 'Shop quality products near you';
    final heroSubtitle =
        _storefront?.heroSubtitle ??
        'Discover deals, compare sellers, and checkout with M-Pesa.';
    final shortcuts = _storefront?.categoryShortcuts ?? const <String>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: MarketplaceGradients.hero(colorScheme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heroTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            heroSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (shortcuts.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final shortcut = shortcuts[index];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(shortcut.replaceAll('_', ' ')),
                    onPressed: () async {
                      setState(() => _selectedCategory = shortcut);
                      await _refresh();
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: shortcuts.length.clamp(0, 8).toInt(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorefrontSections() {
    if (widget.mode != MarketplaceViewMode.home || _savedOnly) {
      return const SizedBox.shrink();
    }
    final sections =
        _storefront?.sections ?? const <MarketplaceStorefrontSection>[];
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Column(
        children: sections.map((section) {
          if (section.products.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: MarketplaceGradients.sectionHeader(
                      Theme.of(context).colorScheme,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (section.subtitle.isNotEmpty)
                        Text(
                          section.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final product = section.products[index];
                      return SizedBox(
                        width: 186,
                        child: ProductCard(
                          product: product,
                          onTap: () => _openProduct(product),
                          onToggleSave: () => _toggleSave(product),
                          onToggleLike: () => _toggleLike(product),
                          onAddToCart:
                              _cartPendingProductIds.contains(product.id)
                              ? null
                              : () => _addToCart(product),
                          rotationTick: _rotationTick,
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemCount: section.products.length.clamp(0, 10).toInt(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Duration _nextDropCountdown() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, 21);
    final target = now.isBefore(next) ? next : next.add(const Duration(days: 1));
    return target.difference(now);
  }

  Future<void> _applyHomeQuickFilter(String filter) async {
    switch (filter) {
      case 'Under 2K':
        _searchController.text = 'under 2000';
        await _onSearchChanged('under 2000');
        break;
      case 'Luxury':
        setState(() {
          _sort = 'PRICE_DESC';
          _selectedCondition = 'NEW';
        });
        await _refresh();
        break;
      case 'Streetwear':
        setState(() {
          _selectedCategory = 'FASHION';
        });
        await _refresh();
        break;
      case 'Near Me':
        setState(() {
          _selectedCounty = widget.defaultCounty;
          _selectedConstituency = widget.defaultConstituency;
          _selectedWard = widget.defaultWard;
        });
        await _refresh();
        break;
      case 'Same-day':
        _showSnack('Showing same-day offers near you');
        break;
    }
  }

  Future<void> _applyMoodFilter(String mood) async {
    if (mood.contains('Bold')) {
      setState(() => _selectedCategory = 'FASHION');
    } else if (mood.contains('Cozy')) {
      setState(() => _selectedCategory = 'HOME');
    } else {
      setState(() {
        _selectedCategory = 'PHONES';
        _sort = 'PRICE_DESC';
      });
    }
    await _refresh();
  }

  Widget _buildCommerceExperienceSections(ColorScheme colorScheme) {
    if (widget.mode != MarketplaceViewMode.home || _savedOnly) {
      return const SizedBox.shrink();
    }

    final displayProducts = _products.isEmpty ? _seedProducts : _products;
    final forYouProducts = displayProducts.take(3).toList();
    final recentProducts = displayProducts.skip(1).take(3).toList();
    final reorderProducts = displayProducts.take(2).toList();
    final locationLabel = widget.defaultCounty ?? 'your area';
    final dropCountdown = _nextDropCountdown();
    final dropClock =
        '${dropCountdown.inHours.toString().padLeft(2, '0')}:${(dropCountdown.inMinutes % 60).toString().padLeft(2, '0')}:${(dropCountdown.inSeconds % 60).toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎯 For You AI Feed',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text('You might like this drip 👀'),
                const SizedBox(height: 8),
                ...forYouProducts.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${product.title} • KES ${product.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: MarketplaceGradients.sectionHeader(colorScheme),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔥 Live Shopping Drops', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('200+ people viewing right now'),
                const SizedBox(height: 6),
                ..._livePurchaseTicker.take(2).map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                _SeedFeatureTile(icon: Icons.play_circle_fill_rounded, title: 'Video previews', subtitle: 'Swipe reels-style clips'),
                _SeedFeatureTile(icon: Icons.style, title: 'Smart bundles', subtitle: 'Complete the look in one tap'),
                _SeedFeatureTile(icon: Icons.casino, title: 'Spin & Win', subtitle: 'Daily rewards and XP points'),
                _SeedFeatureTile(icon: Icons.local_shipping, title: 'Deals near you', subtitle: 'Location-based fast delivery'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _homeQuickFilters
                .map(
                  (chip) => ActionChip(
                    label: Text(chip),
                    onPressed: () => _applyHomeQuickFilter(chip),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _moodFilters
                .map(
                  (mood) => ChoiceChip(
                    label: Text(mood),
                    selected: false,
                    onSelected: (_) => _applyMoodFilter(mood),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⏳ New drop in $dropClock', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('📍 Location deals in $locationLabel • same-day offers available'),
                const SizedBox(height: 6),
                if (recentProducts.isNotEmpty)
                  Text(
                    '⚡ Still thinking about ${recentProducts.first.title}? Only 3 left',
                    style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
                  ),
                const SizedBox(height: 6),
                if (reorderProducts.isNotEmpty)
                  Text(
                    '🧾 Buy again: ${reorderProducts.map((p) => p.title).join(' • ')}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💬 Community Reviews Feed', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ..._communityReviews.map((item) => Text(item, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
                const SizedBox(height: 8),
                const Text('🧑‍🤝‍🧑 Influencer Picks', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ..._influencerPicks.map((item) => Text('• $item', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
                const SizedBox(height: 8),
                const Text('🧠 Smart Search Suggestions', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ..._smartSearchSuggestions.map((item) => Text('• $item', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _secretDealsRevealed = !_secretDealsRevealed),
                  icon: Icon(_secretDealsRevealed ? Icons.visibility_off : Icons.visibility),
                  label: Text(_secretDealsRevealed ? 'Hide secret deals' : 'Tap to reveal secret deals'),
                ),
                if (_secretDealsRevealed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '🎁 Hidden deals unlocked: 12% off gadgets, free delivery on fashion, 2-for-1 accessories',
                      style: TextStyle(fontSize: 12, color: colorScheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedEntries = _buildGridEntries();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fieldFillColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : Colors.grey[100];
    final metaTextColor = colorScheme.onSurfaceVariant;
    final screenWidth = MediaQuery.of(context).size.width;
    final gridColumns = screenWidth >= 840
        ? 3
        : screenWidth >= 370
        ? 2
        : 1;
    final gridAspectRatio = gridColumns == 1 ? 1.12 : 0.72;

    final showInitialLoader = _isLoading && _products.isEmpty;
    final showInitialError =
        _error != null && _products.isEmpty && !_showSeedFallback;

    return Column(
      children: [
        if (widget.mode == MarketplaceViewMode.home && !_savedOnly)
          _buildStorefrontHero(colorScheme),
        _buildCommerceExperienceSections(colorScheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: widget.mode == MarketplaceViewMode.search
                        ? 'Search products, ward, constituency...'
                        : 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              _refresh();
                            },
                            icon: const Icon(Icons.close),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: fieldFillColor,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _openPostProduct,
                icon: const Icon(Icons.add_business_outlined),
                tooltip: 'Post product',
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: _openCartPage,
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Cart',
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: _openFiltersSheet,
                    icon: const Icon(Icons.tune),
                    tooltip: 'Filters',
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _activeFilterCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Icon(
                _savedOnly ? Icons.bookmark : Icons.public,
                size: 16,
                color: metaTextColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _savedOnly ? 'Saved products only' : 'Public products',
                  style: TextStyle(fontSize: 12, color: metaTextColor),
                ),
              ),
              Text(
                _sort.replaceAll('_', ' '),
                style: TextStyle(fontSize: 12, color: metaTextColor),
              ),
            ],
          ),
        ),
        if (!_savedOnly && _activeFilterCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_selectedCategory != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_selectedCategory!),
                    onDeleted: () async {
                      setState(() => _selectedCategory = null);
                      await _refresh();
                    },
                  ),
                if (_selectedCondition != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_selectedCondition!),
                    onDeleted: () async {
                      setState(() => _selectedCondition = null);
                      await _refresh();
                    },
                  ),
                if (_selectedCounty != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      _selectedWard ??
                          _selectedConstituency ??
                          _selectedCounty!,
                    ),
                    onDeleted: () async {
                      setState(() {
                        _selectedCounty = null;
                        _selectedConstituency = null;
                        _selectedWard = null;
                      });
                      await _refresh();
                    },
                  ),
              ],
            ),
          ),
        _buildStorefrontSections(),
        if (!_savedOnly && _marketplaceTopAd != null && _adService != null)
          FeedAdWidget(
            ad: _marketplaceTopAd!,
            adService: _adService!,
            height: 150,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        if (_savedOnly)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing saved products',
                style: TextStyle(fontSize: 12, color: metaTextColor),
              ),
            ),
          ),
        if (_warnings.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _warnings.join(' '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (_error != null && _products.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        if (!_savedOnly && _products.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  _rankingVersion ?? 'marketplace_v2',
                  style: TextStyle(fontSize: 11, color: metaTextColor),
                ),
                Text(
                  'mode: ${_servedMode ?? _preferredLoadMode}',
                  style: TextStyle(fontSize: 11, color: metaTextColor),
                ),
                Text(
                  'location: ${_viewerLocationUsed ?? 'NONE'}',
                  style: TextStyle(fontSize: 11, color: metaTextColor),
                ),
                if (_restrictedFilterApplied)
                  Text(
                    'restricted filter on',
                    style: TextStyle(fontSize: 11, color: metaTextColor),
                  ),
              ],
            ),
          ),
        if (!_savedOnly && _showSeedFallback)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Marketplace is unavailable right now. Showing sample listings while we reconnect.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: showInitialLoader
              ? _buildLoadingSkeletonGrid(
                  colorScheme.surfaceContainerHighest,
                  columns: gridColumns,
                  aspectRatio: gridAspectRatio,
                )
              : showInitialError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: feedEntries.isEmpty
                      ? _buildEmptyState()
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: gridColumns,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: gridAspectRatio,
                              ),
                          itemCount:
                              feedEntries.length + (_isLoadingMore ? 2 : 0),
                          itemBuilder: (context, index) {
                            if (index >= feedEntries.length) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            }
                            final entry = feedEntries[index];
                            if (entry.isAd) {
                              return _buildGridAdCard(entry.ad!);
                            }
                            final product = entry.product!;
                            return ProductCard(
                              product: product,
                              onTap: () => _openProduct(product),
                              onToggleSave: () => _toggleSave(product),
                              onToggleLike: () => _toggleLike(product),
                              onAddToCart:
                                  _cartPendingProductIds.contains(product.id)
                                  ? null
                                  : () => _addToCart(product),
                              rotationTick: _rotationTick,
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

class _MarketplaceGridEntry {
  final MarketplaceProduct? product;
  final Advertisement? ad;

  const _MarketplaceGridEntry._({this.product, this.ad});

  const _MarketplaceGridEntry.product(MarketplaceProduct product)
    : this._(product: product);

  const _MarketplaceGridEntry.ad(Advertisement ad) : this._(ad: ad);

  bool get isAd => ad != null;
}
