import 'package:flutter/material.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/models/rental.dart';
import '../../../core/services/saved_rental_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/telegram/telegram_section_state.dart';
import '../../../core/widgets/telegram/telegram_top_bar.dart';
import '../../../core/services/google_ad_service.dart';
import 'rental_detail_page.dart';

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => SavedPageState();
}

class SavedPageState extends State<SavedPage> {
  static const int _pageSize = 10;

  List<SavedRental> _savedRentals = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int _totalSavedCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSavedRentals();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      _loadSavedRentals(loadMore: true);
    }
  }

  /// Called from AppShell when user switches to the Saved tab
  void refresh() {
    _loadSavedRentals(forceRefresh: true);
  }

  Future<void> _loadSavedRentals({
    bool forceRefresh = false,
    bool loadMore = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      if (mounted) {
        setState(() {
          _savedRentals = [];
          _isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
          _currentPage = 0;
          _totalSavedCount = 0;
        });
      }
      return;
    }

    if (loadMore && (_isLoadingMore || !_hasMore)) return;

    setState(() {
      _error = null;
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        if (forceRefresh) {
          _savedRentals = [];
          _currentPage = 0;
          _hasMore = true;
        }
      }
    });

    try {
      final nextPage = loadMore ? _currentPage + 1 : 0;
      final result = await SavedRentalService.getSavedRentalsPaginated(
        page: nextPage,
        size: _pageSize,
        forceRefresh: forceRefresh,
      );

      setState(() {
        if (loadMore) {
          _savedRentals = [..._savedRentals, ...result.rentals];
        } else {
          _savedRentals = result.rentals;
        }
        _currentPage = result.page;
        _hasMore = result.hasMore;
        _totalSavedCount = result.totalElements;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load saved listings.',
        );
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _unsaveRental(int rentalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Saved'),
        content: const Text(
          'Are you sure you want to remove this listing from your saved items?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await SavedRentalService.unsaveRental(rentalId);
      if (success) {
        setState(() {
          _savedRentals.removeWhere((sr) => sr.rentalId == rentalId);
          if (_totalSavedCount > 0) {
            _totalSavedCount--;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Removed from saved')));
        }

        if (_savedRentals.length < _pageSize && _hasMore) {
          _loadSavedRentals(loadMore: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TelegramTopBar(
            title: 'Saved',
            subtitle: _savedRentals.isNotEmpty
                ? '$_totalSavedCount saved rentals'
                : 'Your bookmarks',
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!AuthService.isLoggedIn) {
      return _buildLoginPrompt();
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildError();
    }

    if (_savedRentals.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadSavedRentals(forceRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        itemCount: _savedRentals.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _savedRentals.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final savedRental = _savedRentals[index];
          final isAdIndex = (index + 1) % 4 == 0;

          return Column(
            children: [
              _SavedRentalCard(
                savedRental: savedRental,
                onTap: () => _navigateToDetail(savedRental.rental),
                onUnsave: () => _unsaveRental(savedRental.rentalId),
              ),
              if (isAdIndex)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Center(child: GoogleAdBannerWidget()),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const TelegramSectionState.empty(
            title: 'Save your favorites',
            subtitle: 'Sign in to save listings and view them later.',
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const TelegramSectionState.empty(
            title: 'No saved listings',
            subtitle: 'Tap bookmark on any listing to save it here.',
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: TelegramSectionState.error(
            title: 'Something went wrong',
            subtitle: _error ?? 'Failed to load saved listings',
            actionLabel: 'Try again',
            onAction: () => _loadSavedRentals(forceRefresh: true),
          ),
        ),
      ],
    );
  }

  void _navigateToDetail(Rental rental) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => RentalDetailPage(rental: rental),
          ),
        )
        .then(
          (_) => _loadSavedRentals(forceRefresh: true),
        ); // Refresh on return
  }
}

class _SavedRentalCard extends StatelessWidget {
  final SavedRental savedRental;
  final VoidCallback onTap;
  final VoidCallback onUnsave;

  const _SavedRentalCard({
    required this.savedRental,
    required this.onTap,
    required this.onUnsave,
  });

  @override
  Widget build(BuildContext context) {
    final rental = savedRental.rental;
    final details =
        '${rental.bedrooms} bed • ${rental.bathrooms} bath • ${rental.squareFeet} sq ft${rental.floor != null ? ' • Floor ${rental.floor}' : ''}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: rental.imageUrls.isNotEmpty
                    ? Image.network(
                        rental.imageUrls.first,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _SavedPlaceholder(),
                      )
                    : const _SavedPlaceholder(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rental.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rental.fullAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                    ),
                    if (savedRental.notes != null &&
                        savedRental.notes!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          savedRental.notes!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.amber[900], fontSize: 12, fontStyle: FontStyle.italic),
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
                    rental.formattedPrice,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.bookmark, color: Colors.deepPurple),
                    onPressed: onUnsave,
                    tooltip: 'Remove from saved',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedPlaceholder extends StatelessWidget {
  const _SavedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.home_work_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
