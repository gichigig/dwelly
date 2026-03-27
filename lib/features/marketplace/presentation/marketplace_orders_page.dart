import 'package:flutter/material.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/models/marketplace_commerce.dart';
import '../../../core/services/marketplace_service.dart';

class MarketplaceOrdersPage extends StatefulWidget {
  final bool sellerMode;

  const MarketplaceOrdersPage({super.key, this.sellerMode = false});

  @override
  State<MarketplaceOrdersPage> createState() => _MarketplaceOrdersPageState();
}

class _MarketplaceOrdersPageState extends State<MarketplaceOrdersPage> {
  final List<MarketplaceOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = widget.sellerMode
          ? await MarketplaceService.getSellerOrders()
          : await MarketplaceService.getMyOrders();
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(page.orders);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userErrorMessage(e, fallbackMessage: 'Failed to load orders.');
      });
    }
  }

  Future<void> _updateSellerStatus(
    MarketplaceOrder order,
    String status,
  ) async {
    try {
      await MarketplaceService.updateSellerOrderFulfillment(
        order.id,
        status: status,
      );
      if (!mounted) return;
      _showSnack('Order updated to $status');
      _loadOrders();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to update order status.',
      );
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    return switch (status) {
      'DELIVERED' => Colors.green,
      'CANCELLED' => Colors.red,
      'AWAITING_PAYMENT' => Colors.orange,
      _ => scheme.primary,
    };
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sellerMode ? 'Seller Orders' : 'My Orders'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _loadOrders,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _orders.isEmpty
          ? const Center(child: Text('No orders yet.'))
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  final statusColor = _statusColor(order.status, scheme);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Order #${order.id}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(order.status),
                                side: BorderSide(
                                  color: statusColor.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Payment: ${order.paymentStatus} • ${order.paymentMethod}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total: KES ${order.total.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ...(order.items
                              .take(3)
                              .map(
                                (line) => Text(
                                  '${line.quantity}x ${line.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              )),
                          if (widget.sellerMode) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statusAction(order, 'PROCESSING'),
                                _statusAction(order, 'SHIPPED'),
                                _statusAction(order, 'DELIVERED'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemCount: _orders.length,
              ),
            ),
    );
  }

  Widget _statusAction(MarketplaceOrder order, String status) {
    final disabled = order.status == status || order.status == 'CANCELLED';
    return OutlinedButton(
      onPressed: disabled ? null : () => _updateSellerStatus(order, status),
      child: Text(status),
    );
  }
}
