import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/api_service.dart';
import 'package:realestate/core/services/dwelly_media_cache_manager.dart';
import 'package:realestate/core/widgets/progressive_image.dart';

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
  }) : width = size,
       height = size,
       borderRadius = null,
       shape = BoxShape.circle;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBase = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    final base = widget.baseColor ?? defaultBase;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.rectangle
            ? (widget.borderRadius ?? BorderRadius.circular(8.0))
            : null,
      ),
    );
  }
}

/// A drop-in replacement for CachedNetworkImage that automatically applies
/// Dwelly's signature Shimmer Wave loading placeholder and smooth fade transitions.
///
/// Optimized for performance: uses [memCacheWidth] and [memCacheHeight] to avoid
/// decoding full-resolution images into memory when displayed at smaller sizes.
///
/// Supports progressive loading: when [thumbnailUrl] and/or [mediumUrl] are provided,
/// the widget loads images in tiers (thumbnail → medium → full) with smooth crossfades.
class DwellyNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final BoxShape shape;

  /// Override the memory cache width. If null, auto-calculated from [width].
  final int? memCacheWidth;

  /// Override the memory cache height. If null, auto-calculated from [height].
  final int? memCacheHeight;

  /// Explicit thumbnail URL for progressive loading. If provided, used instead of URL derivation.
  final String? thumbnailUrl;

  /// Explicit medium-resolution URL for progressive loading.
  final String? mediumUrl;

  /// Whether to load the full-resolution image. Set to false for feed cards.
  final bool loadFull;

  const DwellyNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
    this.shape = BoxShape.rectangle,
    this.memCacheWidth,
    this.memCacheHeight,
    this.thumbnailUrl,
    this.mediumUrl,
    this.loadFull = false,
  });

  @override
  State<DwellyNetworkImage> createState() => _DwellyNetworkImageState();
}

class _DwellyNetworkImageState extends State<DwellyNetworkImage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate memory cache dimensions:
    // Use explicit override > auto-calculate from widget size at 2x device pixel ratio > default cap
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final effectiveMemCacheWidth =
        widget.memCacheWidth ??
        (widget.width != null
            ? (widget.width! * dpr).round().clamp(1, 1200)
            : 800);
    final effectiveMemCacheHeight =
        widget.memCacheHeight ??
        (widget.height != null
            ? (widget.height! * dpr).round().clamp(1, 1200)
            : null);

    // Determine the best thumbnail URL: explicit > derived > fallback
    final explicitThumb = widget.thumbnailUrl;
    final derivedThumb = ApiService.getFeedThumbnailUrl(widget.imageUrl);
    final effectiveThumbUrl =
        (explicitThumb != null && explicitThumb.isNotEmpty)
        ? ApiService.resolveMediaUrl(explicitThumb)
        : (derivedThumb.isNotEmpty ? derivedThumb : null);

    final effectiveMediumUrl =
        (widget.mediumUrl != null && widget.mediumUrl!.isNotEmpty)
        ? ApiService.resolveMediaUrl(widget.mediumUrl!)
        : null;

    final effectiveFullUrl = ApiService.resolveMediaUrl(widget.imageUrl);

    final fallbackPlaceholder = Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : const Color(0xFFE2E8F0),
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.rectangle
            ? (widget.borderRadius ?? BorderRadius.circular(8.0))
            : null,
      ),
    );

    Widget buildCachedImage(String url, Widget placeholderWidget) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheManager: DwellyMediaCacheManager.instance,
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        fit: widget.fit,
        memCacheWidth: effectiveMemCacheWidth,
        memCacheHeight: effectiveMemCacheHeight,
        fadeInDuration: const Duration(milliseconds: 250),
        fadeOutDuration: const Duration(milliseconds: 250),
        placeholder: (context, url) => placeholderWidget,
        errorWidget: (context, url, error) =>
            widget.errorWidget ?? _buildDefaultError(context),
      );
    }

    Widget content;
    final hasFull = effectiveFullUrl != null && effectiveFullUrl.isNotEmpty;
    final hasMedium = effectiveMediumUrl != null && effectiveMediumUrl.isNotEmpty;
    final hasThumb = effectiveThumbUrl != null && effectiveThumbUrl.isNotEmpty;

    if (hasFull && widget.loadFull) {
      if (hasMedium) {
        content = buildCachedImage(
          effectiveFullUrl,
          buildCachedImage(
            effectiveMediumUrl,
            hasThumb ? buildCachedImage(effectiveThumbUrl, fallbackPlaceholder) : fallbackPlaceholder,
          ),
        );
      } else if (hasThumb) {
        content = buildCachedImage(
          effectiveFullUrl,
          buildCachedImage(effectiveThumbUrl, fallbackPlaceholder),
        );
      } else {
        content = buildCachedImage(effectiveFullUrl, fallbackPlaceholder);
      }
    } else if (hasMedium) {
      if (hasThumb) {
        content = buildCachedImage(
          effectiveMediumUrl,
          buildCachedImage(effectiveThumbUrl, fallbackPlaceholder),
        );
      } else {
        content = buildCachedImage(effectiveMediumUrl, fallbackPlaceholder);
      }
    } else if (hasThumb) {
      content = buildCachedImage(effectiveThumbUrl, fallbackPlaceholder);
    } else if (hasFull) {
      content = buildCachedImage(effectiveFullUrl, fallbackPlaceholder);
    } else {
      content = widget.errorWidget ?? fallbackPlaceholder;
    }

    if (widget.borderRadius != null && widget.shape == BoxShape.rectangle) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: content);
    } else if (widget.shape == BoxShape.circle) {
      return ClipOval(child: content);
    }
    return content;
  }

  Widget _buildDefaultError(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: widget.shape == BoxShape.rectangle
            ? widget.borderRadius
            : null,
        shape: widget.shape,
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: isDark ? Colors.white38 : Colors.black38,
          size: (widget.width != null && widget.width! < 50) ? 18 : 28,
        ),
      ),
    );
  }
}
