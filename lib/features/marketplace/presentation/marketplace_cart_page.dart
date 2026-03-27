import 'package:flutter/material.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/models/marketplace_commerce.dart';
import '../../../core/services/marketplace_service.dart';

class MarketplaceCartPage extends StatefulWidget {
  const MarketplaceCartPage({super.key});

  @override
  State<MarketplaceCartPage> createState() => _MarketplaceCartPageState();
}

class _MarketplaceCartPageState extends State<MarketplaceCartPage> {
  MarketplaceCart _cart = const MarketplaceCart.empty();
  bool _loading = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cart = await MarketplaceService.getCart(
        requestTimeout: const Duration(seconds: 4),
      );
      if (!mounted) return;
      setState(() {
        _cart = cart;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(e, fallbackMessage: 'Failed to load cart.');
        _loading = false;
      });
    }
  }

  Future<void> _changeQuantity(
    MarketplaceCartItem item,
    int nextQuantity,
  ) async {
    if (nextQuantity < 1) return;
    setState(() => _processing = true);
    try {
      final cart = await MarketplaceService.updateCartItem(
        item.itemId,
        quantity: nextQuantity,
      );
      if (!mounted) return;
      setState(() => _cart = cart);
    } catch (e) {
      if (!mounted) return;
      _showError(e, 'Failed to update quantity.');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _removeItem(MarketplaceCartItem item) async {
    setState(() => _processing = true);
    try {
      final cart = await MarketplaceService.removeCartItem(item.itemId);
      if (!mounted) return;
      setState(() => _cart = cart);
    } catch (e) {
      if (!mounted) return;
      _showError(e, 'Failed to remove item.');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _startCheckout() async {
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    String deliveryType = 'BOTH';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Checkout',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: deliveryType,
                      items: const [
                        DropdownMenuItem(
                          value: 'BOTH',
                          child: Text('Delivery or Pickup'),
                        ),
                        DropdownMenuItem(
                          value: 'DELIVERY',
                          child: Text('Delivery only'),
                        ),
                        DropdownMenuItem(
                          value: 'PICKUP',
                          child: Text('Pickup only'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => deliveryType = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Fulfillment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'M-Pesa Phone',
                        hintText: '07XXXXXXXX or 2547XXXXXXXX',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Delivery Address (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (phoneController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter M-Pesa phone number',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.of(context).pop(true);
                        },
                        child: const Text('Pay with M-Pesa'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (confirmed != true) {
      phoneController.dispose();
      addressController.dispose();
      return;
    }

    setState(() => _processing = true);
    try {
      final order = await MarketplaceService.checkout(
        mpesaPhone: phoneController.text.trim(),
        deliveryType: deliveryType,
        deliveryAddress: addressController.text.trim(),
      );
      final result = await MarketplaceService.startOrderMpesa(
        order.id,
        phoneNumber: phoneController.text.trim(),
      );
      if (!mounted) return;
      await _loadCart();
      final text = result.customerMessage?.isNotEmpty == true
          ? result.customerMessage!
          : 'M-Pesa prompt sent. Complete payment on your phone.';
      _showSnack(text);
    } catch (e) {
      if (!mounted) return;
      _showError(e, 'Checkout failed.');
    } finally {
      phoneController.dispose();
      addressController.dispose();
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  void _showError(Object error, String fallback) {
    showErrorSnackBar(context, error, fallbackMessage: fallback);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Cart')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _loadCart,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _cart.items.isEmpty
          ? const Center(child: Text('Your cart is empty.'))
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    itemBuilder: (context, index) {
                      final item = _cart.items[index];
                      return Card(
                        child: ListTile(
                          leading: item.imageUrl == null
                              ? const Icon(Icons.image_not_supported)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item.imageUrl!,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'KES ${item.unitPrice.toStringAsFixed(0)} • ${item.deliveryType}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: _processing
                                    ? null
                                    : () => _changeQuantity(
                                        item,
                                        item.quantity - 1,
                                      ),
                              ),
                              Text('${item.quantity}'),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _processing
                                    ? null
                                    : () => _changeQuantity(
                                        item,
                                        item.quantity + 1,
                                      ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _processing
                                    ? null
                                    : () => _removeItem(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemCount: _cart.items.length,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _row('Subtotal', _cart.subtotal),
                      _row('Delivery', _cart.deliveryFee),
                      const SizedBox(height: 6),
                      _row('Total', _cart.total, bold: true),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _processing ? null : _startCheckout,
                          child: Text(
                            _processing
                                ? 'Processing...'
                                : 'Checkout with M-Pesa',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, double value, {bool bold = false}) {
    final textStyle = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 15 : 13,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyle)),
          Text('KES ${value.toStringAsFixed(0)}', style: textStyle),
        ],
      ),
    );
  }
}
