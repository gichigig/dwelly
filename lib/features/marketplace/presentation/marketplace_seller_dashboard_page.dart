import 'package:flutter/material.dart';

import '../../../core/models/marketplace_product.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/auth_gate_card.dart';
import 'marketplace_orders_page.dart';
import 'post_product_page.dart';

class MarketplaceSellerDashboardPage extends StatefulWidget {
  final List<MarketplaceProduct> initialProducts;

  const MarketplaceSellerDashboardPage({
    super.key,
    this.initialProducts = const <MarketplaceProduct>[],
  });

  @override
  State<MarketplaceSellerDashboardPage> createState() =>
      _MarketplaceSellerDashboardPageState();
}

class _MarketplaceSellerDashboardPageState
    extends State<MarketplaceSellerDashboardPage> {
  static const Duration _firstLoadTimeout = Duration(milliseconds: 4500);

  final List<MarketplaceProduct> _products = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'ALL';
  int _totalProducts = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialProducts.isNotEmpty) {
      _products.addAll(widget.initialProducts);
      _totalProducts = widget.initialProducts.length;
      _isLoading = false;
    }
    _loadProducts(background: widget.initialProducts.isNotEmpty);
  }

  Future<void> _loadProducts({bool background = false}) async {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _products.clear();
      });
      return;
    }

    setState(() {
      _isLoading = !background && _products.isEmpty;
      _error = null;
    });

    try {
      final result = await _fetchProducts(allowRetry: _products.isEmpty);
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(result.products);
        _totalProducts = result.totalElements;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load seller dashboard.',
        );
        _isLoading = false;
      });
    }
  }

  Future<PaginatedMarketplaceProducts> _fetchProducts({
    required bool allowRetry,
  }) async {
    try {
      return await MarketplaceService.getMyProducts(
        page: 0,
        size: 50,
        requestTimeout: _firstLoadTimeout,
      );
    } catch (e) {
      if (!allowRetry) rethrow;
      await Future.delayed(const Duration(milliseconds: 300));
      return MarketplaceService.getMyProducts(
        page: 0,
        size: 50,
        requestTimeout: _firstLoadTimeout,
      );
    }
  }

  Iterable<MarketplaceProduct> get _visibleProducts {
    if (_statusFilter == 'ALL') return _products;
    return _products.where((p) => p.status == _statusFilter);
  }

  int _countByStatus(String status) =>
      _products.where((p) => p.status == status).length;

  Future<void> _openPost() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PostProductPage()));
    if (created == true && mounted) {
      _loadProducts();
    }
  }

  Future<void> _editProduct(MarketplaceProduct product) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostProductPage(editingProduct: product),
      ),
    );
    if (updated == true && mounted) {
      _loadProducts();
    }
  }

  Future<void> _updateStatus(MarketplaceProduct product, String status) async {
    if (product.id == null) return;
    try {
      await MarketplaceService.updateStatus(product.id!, status);
      if (!mounted) return;
      _showSnack('Status updated to $status');
      _loadProducts();
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to update product status. Please try again.',
      );
    }
  }

  Future<void> _requestSponsorship(MarketplaceProduct product) async {
    if (product.id == null) return;
    try {
      await MarketplaceService.requestProductSponsorship(product.id!);
      _showSnack('Sponsorship request submitted');
      _loadProducts();
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to request sponsorship. Please try again.',
      );
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

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AuthGateCard(
          title: 'Sign in to sell products',
          subtitle:
              'Manage your product listings, status, and sponsorship requests.',
          onSignIn: () => showLoginBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadProducts();
            },
          ),
          onCreateAccount: () => showSignupBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadProducts();
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
            const Text('Failed to load seller dashboard'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final products = _visibleProducts.toList();

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (_error != null && _products.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InlineRetryBanner(
                message: _error!,
                onRetry: _loadProducts,
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seller Dashboard',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text('Total products: $_totalProducts'),
                  Text('Active: ${_countByStatus('ACTIVE')}'),
                  Text('Sold: ${_countByStatus('SOLD')}'),
                  Text('Inactive: ${_countByStatus('INACTIVE')}'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openPost,
                          icon: const Icon(Icons.add),
                          label: const Text('Post Product'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MarketplaceOrdersPage(
                                  sellerMode: true,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Orders'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: ['ALL', 'ACTIVE', 'SOLD', 'INACTIVE']
                .map(
                  (status) => ChoiceChip(
                    label: Text(status),
                    selected: _statusFilter == status,
                    onSelected: (_) => setState(() => _statusFilter = status),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: Text('No products for this filter')),
            ),
          ...products.map((product) => _buildProductTile(product)),
        ],
      ),
    );
  }

  Widget _buildProductTile(MarketplaceProduct product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Chip(
                  label: Text(product.status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(product.formattedPrice),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _editProduct(product),
                  child: const Text('Edit'),
                ),
                OutlinedButton(
                  onPressed: () => _updateStatus(product, 'ACTIVE'),
                  child: const Text('Mark Active'),
                ),
                OutlinedButton(
                  onPressed: () => _updateStatus(product, 'SOLD'),
                  child: const Text('Mark Sold'),
                ),
                OutlinedButton(
                  onPressed: () => _updateStatus(product, 'INACTIVE'),
                  child: const Text('Mark Inactive'),
                ),
                FilledButton.tonal(
                  onPressed: () => _requestSponsorship(product),
                  child: const Text('Request Sponsorship'),
                ),
              ],
            ),
          ],
        ),
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
