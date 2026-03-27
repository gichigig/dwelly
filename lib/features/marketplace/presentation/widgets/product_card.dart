import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../core/theme/marketplace_theme.dart';
import '../../../../core/models/marketplace_product.dart';

class ProductCard extends StatefulWidget {
  final MarketplaceProduct product;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final VoidCallback onToggleLike;
  final VoidCallback? onAddToCart;
  final ValueNotifier<int> rotationTick;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onToggleSave,
    required this.onToggleLike,
    this.onAddToCart,
    required this.rotationTick,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return VisibilityDetector(
      key: ValueKey('marketplace-card-${product.id ?? product.title}'),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.55;
        if (visible != _isVisible && mounted) {
          setState(() => _isVisible = visible);
        }
      },
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.rotationTick,
                  builder: (_, tick, __) {
                    final imageUrl = _resolveImageUrl(
                      product,
                      _isVisible ? tick : 0,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildImageFallback(),
                          )
                        else
                          _buildImageFallback(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: MarketplaceGradients.cardAccent(
                                  Theme.of(context).colorScheme,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Row(
                            children: [
                              if (product.sellerMarketplaceBadge)
                                _buildChip(
                                  label: 'Verified',
                                  icon: Icons.verified,
                                  bg: Colors.blue.withValues(alpha: 0.88),
                                ),
                              if (product.sponsored) ...[
                                if (product.sellerMarketplaceBadge)
                                  const SizedBox(width: 4),
                                _buildChip(
                                  label: 'Sponsored',
                                  icon: Icons.campaign,
                                  bg: Colors.deepOrange.withValues(alpha: 0.88),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (product.hasDiscount)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: _buildChip(
                              label: '-${product.discountPercent}%',
                              icon: Icons.local_offer,
                              bg: Colors.green.withValues(alpha: 0.9),
                            ),
                          ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: InkWell(
                            onTap: widget.onToggleSave,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                product.savedByViewer
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          product.formattedPrice,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              product.formattedOriginalPrice,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          product.averageRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${product.ratingCount})',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        _buildStockChip(product),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.shortLocation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                    if ((product.estimatedDeliveryText ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.estimatedDeliveryText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            product.condition.replaceAll('_', ' '),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: widget.onToggleLike,
                          borderRadius: BorderRadius.circular(99),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  product.likedByViewer
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 15,
                                  color: product.likedByViewer
                                      ? Colors.red
                                      : Colors.grey[700],
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${product.likeCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onAddToCart != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: product.inStock
                              ? widget.onAddToCart
                              : null,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          child: Text(
                            product.inStock ? 'Add to Cart' : 'Out of Stock',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _resolveImageUrl(MarketplaceProduct product, int tick) {
    if (product.imageUrls.isEmpty) return null;
    if (product.imageUrls.length == 1) return product.imageUrls.first;
    return product.imageUrls[tick % product.imageUrls.length];
  }

  Widget _buildImageFallback() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.image_not_supported),
    );
  }

  Widget _buildStockChip(MarketplaceProduct product) {
    final color = !product.inStock
        ? Colors.red.withValues(alpha: 0.18)
        : product.isLowStock
        ? Colors.orange.withValues(alpha: 0.2)
        : Colors.green.withValues(alpha: 0.2);
    final label = !product.inStock
        ? 'Out'
        : product.isLowStock
        ? 'Low'
        : 'Stock';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
