import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/rental.dart';
import '../../../core/services/rental_service.dart';
import '../../listings/presentation/rental_detail_page.dart';
import '../../../core/errors/ui_error.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class HashtagSearchPage extends StatefulWidget {
  final String hashtag;

  const HashtagSearchPage({super.key, required this.hashtag});

  @override
  State<HashtagSearchPage> createState() => _HashtagSearchPageState();
}

class _HashtagSearchPageState extends State<HashtagSearchPage> {
  late String _currentQuery;
  bool _isHashtagQuery = true;
  final ScrollController _scrollController = ScrollController();
  List<Rental> _rentals = [];
  List<Rental> _nearbyRentals = [];
  List<String> _relatedHashtags = [];
  List<String> _relatedAreas = [];
  int _currentPage = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchQueryRentals(widget.hashtag);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore || !_hasMore) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _fetchQueryRentals(String query, {bool loadMore = false}) async {
    final normalizedQuery = query.trim();
    final isHashtagQuery = normalizedQuery.startsWith('#');
    final queryToUse = isHashtagQuery ? normalizedQuery : normalizedQuery;

    setState(() {
      _isHashtagQuery = isHashtagQuery;
      _currentQuery = queryToUse;
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _currentPage = 0;
        _hasMore = false;
        _rentals = [];
        _nearbyRentals = [];
        _relatedHashtags = [];
        _relatedAreas = [];
      }
      _error = null;
    });

    try {
      if (isHashtagQuery) {
        final result = await RentalService.searchByHashtag(
          hashtag: _currentQuery,
          page: loadMore ? _currentPage : 0,
          size: 20,
        );

        if (mounted) {
          setState(() {
            _rentals = loadMore ? [..._rentals, ...result.rentals] : result.rentals;
            _nearbyRentals = loadMore
                ? [..._nearbyRentals, ...result.nearbyRentals]
                : result.nearbyRentals;
            _relatedHashtags = loadMore ? _relatedHashtags : result.relatedHashtags;
            _relatedAreas = loadMore ? _relatedAreas : result.relatedAreas;
            _currentPage = result.currentPage + 1;
            _hasMore = result.hasMore;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      final result = await RentalService.searchWithNearbyAreas(
        searchArea: normalizedQuery,
        page: loadMore ? _currentPage : 0,
        size: 20,
      );

      if (mounted) {
        setState(() {
          _rentals = loadMore ? [..._rentals, ...result.rentals] : result.rentals;
          _nearbyRentals = [];
          _relatedHashtags = [];
          _relatedAreas = [];
          _currentPage = result.currentPage + 1;
          _hasMore = result.hasMore;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userErrorMessage(
            e,
            fallbackMessage: 'Failed to load hashtag rentals.',
          );
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    await _fetchQueryRentals(_currentQuery, loadMore: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          _currentQuery,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: DwellyOrbitingLoader());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchQueryRentals(_currentQuery),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    final displayList = _rentals.isNotEmpty ? _rentals : _nearbyRentals;
    final isShowingNearbyFallback =
        _rentals.isEmpty && _nearbyRentals.isNotEmpty;

    if (displayList.isEmpty &&
        _relatedHashtags.isEmpty &&
        _relatedAreas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No listings found for $_currentQuery'),
          ],
        ),
      );
    }

    final firstTwo = displayList.take(2).toList();
    final remaining = displayList.skip(2).toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (isShowingNearbyFallback)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No exact matches for $_currentQuery. Showing nearby listings:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (firstTwo.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCard(firstTwo[index], theme),
                childCount: firstTwo.length,
              ),
            ),
          ),
        if (_isHashtagQuery &&
            (_relatedHashtags.isNotEmpty || _relatedAreas.isNotEmpty))
          SliverToBoxAdapter(child: _buildRecommendationsSection(theme)),
        if (remaining.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCard(remaining[index], theme),
                childCount: remaining.length,
              ),
            ),
          ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: DwellyOrbitingLoader()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildRecommendationsSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.explore, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Similar Areas & Hashtags',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ..._relatedHashtags.map((tag) {
                  final displayTag = tag.startsWith('#') ? tag : '#$tag';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(
                        displayTag,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      onPressed: () => _fetchQueryRentals(displayTag),
                    ),
                  );
                }),
                ..._relatedAreas.map((area) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.location_on, size: 14),
                      label: Text(
                        area,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      onPressed: () => _fetchQueryRentals(area),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Rental rental, ThemeData theme) {
    final photoUrl = rental.imageUrls.isNotEmpty
        ? rental.imageUrls.first
        : 'https://via.placeholder.com/400x300';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RentalDetailPage(rental: rental),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: theme.colorScheme.surfaceVariant),
                    errorWidget: (context, url, error) => Container(
                      color: theme.colorScheme.surfaceVariant,
                      child: const Icon(Icons.home, color: Colors.grey),
                    ),
                  ),
                  if (rental.ownerIsVerified)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'VERIFIED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      rental.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      rental.displayLocation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      rental.formattedPrice,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
