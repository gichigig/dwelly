import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/models/marketplace_product.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/auth_gate_card.dart';
import 'product_detail_page.dart';
import 'widgets/product_card.dart';

class MarketplaceSavedPage extends StatefulWidget {
  final List<MarketplaceProduct> initialProducts;

  const MarketplaceSavedPage({
    super.key,
    this.initialProducts = const <MarketplaceProduct>[],
  });

  @override
  State<MarketplaceSavedPage> createState() => _MarketplaceSavedPageState();
}

class _MarketplaceSavedPageState extends State<MarketplaceSavedPage> {
  static const int _pageSize = 10;
  static const Duration _firstLoadTimeout = Duration(milliseconds: 4500);

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _rotationTick = ValueNotifier<int>(0);
  Timer? _rotationTimer;

  final List<MarketplaceProduct> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _startRotationTicker();
    if (widget.initialProducts.isNotEmpty) {
      _products.addAll(widget.initialProducts);
      _isLoading = false;
      _hasMore = widget.initialProducts.length >= _pageSize;
    }
    _loadSaved(refresh: _products.isEmpty, background: _products.isNotEmpty);
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _rotationTick.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startRotationTicker() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _rotationTick.value = _rotationTick.value + 1;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      _loadSaved();
    }
  }

  Future<void> _loadSaved({
    bool refresh = false,
    bool background = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _products.clear();
      });
      return;
    }

    if (refresh) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _error = null;
        _products.clear();
        _currentPage = 0;
        _hasMore = true;
      });
    } else if (background) {
      setState(() => _error = null);
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() {
        _isLoadingMore = true;
        _error = null;
      });
    }

    try {
      final nextPage = refresh ? 0 : _currentPage + 1;
      final result = await _fetchSavedPage(
        page: nextPage,
        allowRetry: refresh && _products.isEmpty,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _products
            ..clear()
            ..addAll(result.products);
        } else {
          _products.addAll(result.products);
        }
        _currentPage = result.currentPage;
        _hasMore = result.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load saved products.',
        );
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<PaginatedMarketplaceProducts> _fetchSavedPage({
    required int page,
    required bool allowRetry,
  }) async {
    try {
      return await MarketplaceService.getSavedProducts(
        page: page,
        size: _pageSize,
        requestTimeout: _firstLoadTimeout,
      );
    } catch (e) {
      if (!allowRetry) rethrow;
      await Future.delayed(const Duration(milliseconds: 320));
      return MarketplaceService.getSavedProducts(
        page: page,
        size: _pageSize,
        requestTimeout: _firstLoadTimeout,
      );
    }
  }

  Future<void> _toggleSave(MarketplaceProduct product) async {
    if (product.id == null) return;
    try {
      await MarketplaceService.unsaveProduct(product.id!);
      if (!mounted) return;
      setState(() {
        _products.removeWhere((p) => p.id == product.id);
      });
    } catch (e) {
      _showSnack(
        userErrorMessage(e, fallbackMessage: 'Failed to update saved product.'),
      );
    }
  }

  Future<void> _toggleLike(MarketplaceProduct product) async {
    if (!AuthService.isLoggedIn || product.id == null) return;
    try {
      final updated = product.likedByViewer
          ? await MarketplaceService.unlikeProduct(product.id!)
          : await MarketplaceService.likeProduct(product.id!);
      if (!mounted) return;
      setState(() {
        final index = _products.indexWhere((p) => p.id == product.id);
        if (index >= 0) {
          _products[index] = updated.copyWith(savedByViewer: true);
        }
      });
    } catch (e) {
      _showSnack(
        userErrorMessage(e, fallbackMessage: 'Failed to update like.'),
      );
    }
  }

  Future<void> _openDetails(MarketplaceProduct product) async {
    if (product.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(productId: product.id!),
      ),
    );
    if (!mounted) return;
    _loadSaved(refresh: true);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AuthGateCard(
          title: 'Sign in to view saved products',
          subtitle: 'Your marketplace bookmarks are linked to your account.',
          onSignIn: () => showLoginBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadSaved(refresh: true);
            },
          ),
          onCreateAccount: () => showSignupBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadSaved(refresh: true);
            },
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load saved products'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loadSaved(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Text(
          'No saved products yet',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadSaved(refresh: true),
      child: Column(
        children: [
          if (_error != null && _products.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _InlineRetryBanner(
                message: _error!,
                onRetry: () => _loadSaved(refresh: true),
              ),
            ),
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                crossAxisSpacing: 0,
                mainAxisSpacing: 8,
                childAspectRatio: 1.24,
              ),
              itemCount: _products.length + (_isLoadingMore ? 2 : 0),
              itemBuilder: (context, index) {
                if (index >= _products.length) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final product = _products[index];
                return ProductCard(
                  product: product,
                  onTap: () => _openDetails(product),
                  onToggleSave: () => _toggleSave(product),
                  onToggleLike: () => _toggleLike(product),
                  rotationTick: _rotationTick,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineRetryBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineRetryBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
