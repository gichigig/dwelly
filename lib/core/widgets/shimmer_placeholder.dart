import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A modern, high-performance Skeleton Shimmer Wave placeholder for Dwelly.
/// Animates a sleek horizontal light-wave across containers while images or content load.
class ShimmerPlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.baseColor,
    this.highlightColor,
  });

  /// Factory constructor for circular avatar placeholders
  const ShimmerPlaceholder.circle({
    super.key,
    required double size,
    this.baseColor,
    this.highlightColor,
  })  : width = size,
        height = size,
        borderRadius = null,
        shape = BoxShape.circle;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBase = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final defaultHighlight = isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC);

    final base = widget.baseColor ?? defaultBase;
    final highlight = widget.highlightColor ?? defaultHighlight;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.rectangle
                ? (widget.borderRadius ?? BorderRadius.circular(8.0))
                : null,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1.0, -0.3),
              end: Alignment(_animation.value, 0.3),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// A drop-in replacement for CachedNetworkImage that automatically applies
/// Dwelly's signature Shimmer Wave loading placeholder and smooth fade transitions.
class DwellyNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final BoxShape shape;

  const DwellyNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 350),
      fadeOutDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => ShimmerPlaceholder(
        width: width,
        height: height,
        shape: shape,
        borderRadius: borderRadius,
      ),
      errorWidget: (context, url, error) => errorWidget ?? _buildDefaultError(context),
    );

    if (borderRadius != null && shape == BoxShape.rectangle) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    } else if (shape == BoxShape.circle) {
      return ClipOval(child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildDefaultError(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        shape: shape,
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: isDark ? Colors.white38 : Colors.black38,
          size: (width != null && width! < 50) ? 18 : 28,
        ),
      ),
    );
  }
}
