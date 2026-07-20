import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/api_service.dart';
import 'package:realestate/core/services/dwelly_media_cache_manager.dart';
import 'shimmer_placeholder.dart';

/// Tier levels for progressive image loading.
enum _ImageTier { loading, thumbnail, medium, full }

/// A widget that progressively loads images through three quality tiers:
///   1. Thumbnail (tiny, ~15-20 KB, loads in <100ms)
///   2. Medium (mid-res, ~80-100 KB, for detail views)
///   3. Full (original compressed, ~250-400 KB, for full-screen gallery)
///
/// Each tier crossfades smoothly into the next.
/// Falls back gracefully: if only some URLs are available, it skips missing tiers.
class ProgressiveImage extends StatefulWidget {
  /// The thumbnail URL (smallest variant, ~400x300).
  final String? thumbnailUrl;

  /// The medium URL (mid-res variant, ~960x720).
  final String? mediumUrl;

  /// The full-resolution URL (compressed original, ~1920x1440).
  final String? fullUrl;

  /// How to inscribe the image into the available space.
  final BoxFit fit;

  /// Width constraint.
  final double? width;

  /// Height constraint.
  final double? height;

  /// Border radius for clipping.
  final BorderRadius? borderRadius;

  /// Widget to show on error.
  final Widget? errorWidget;

  /// Whether to load the full-resolution tier.
  /// Set to false for feed cards where medium is sufficient.
  final bool loadFull;

  /// Memory cache width hint for decoded image.
  final int? memCacheWidth;

  /// Memory cache height hint for decoded image.
  final int? memCacheHeight;

  const ProgressiveImage({
    super.key,
    this.thumbnailUrl,
    this.mediumUrl,
    this.fullUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.errorWidget,
    this.loadFull = true,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<ProgressiveImage> createState() => _ProgressiveImageState();
}

class _ProgressiveImageState extends State<ProgressiveImage> {
  _ImageTier _currentTier = _ImageTier.loading;
  ImageProvider? _currentImage;
  int _loadSessionId = 0;
  final List<ImageStreamListener> _activeListeners = [];
  final List<ImageStream> _activeStreams = [];

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void didUpdateWidget(ProgressiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl ||
        oldWidget.mediumUrl != widget.mediumUrl ||
        oldWidget.fullUrl != widget.fullUrl) {
      _cancelActiveLoads();
      _loadSessionId++;
      _currentTier = _ImageTier.loading;
      _currentImage = null;
      _startLoading();
    }
  }

  @override
  void dispose() {
    _cancelActiveLoads();
    super.dispose();
  }

  void _cancelActiveLoads() {
    for (int i = 0; i < _activeStreams.length; i++) {
      _activeStreams[i].removeListener(_activeListeners[i]);
    }
    _activeStreams.clear();
    _activeListeners.clear();
  }

  void _startLoading() {
    final thumbUrl = _resolveUrl(widget.thumbnailUrl);
    final medUrl = _resolveUrl(widget.mediumUrl);
    final fullUrl = _resolveUrl(widget.fullUrl);

    final sessionId = _loadSessionId;

    // Start loading thumbnail
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      _loadTier(thumbUrl, _ImageTier.thumbnail, sessionId, () {
        // After thumbnail loads, start loading medium
        if (medUrl != null && medUrl.isNotEmpty) {
          _loadTier(medUrl, _ImageTier.medium, sessionId, () {
            // After medium loads, optionally load full
            if (widget.loadFull && fullUrl != null && fullUrl.isNotEmpty) {
              _loadTier(fullUrl, _ImageTier.full, sessionId, () {});
            }
          });
        } else if (widget.loadFull && fullUrl != null && fullUrl.isNotEmpty) {
          // No medium available, skip to full
          _loadTier(fullUrl, _ImageTier.full, sessionId, () {});
        }
      });
    } else if (medUrl != null && medUrl.isNotEmpty) {
      // No thumbnail, start from medium
      _loadTier(medUrl, _ImageTier.medium, sessionId, () {
        if (widget.loadFull && fullUrl != null && fullUrl.isNotEmpty) {
          _loadTier(fullUrl, _ImageTier.full, sessionId, () {});
        }
      });
    } else if (fullUrl != null && fullUrl.isNotEmpty) {
      // No thumbnail or medium, load full directly
      _loadTier(fullUrl, _ImageTier.full, sessionId, () {});
    }
  }

  void _loadTier(String url, _ImageTier tier, int sessionId, VoidCallback onLoaded) {
    if (_loadSessionId != sessionId) return;

    final imageProvider = CachedNetworkImageProvider(
      url,
      cacheManager: DwellyMediaCacheManager.instance,
      maxWidth: widget.memCacheWidth,
      maxHeight: widget.memCacheHeight,
    );

    final stream = imageProvider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool syncCall) {
        if (!mounted || _loadSessionId != sessionId) return;
        
        // Only upgrade — never downgrade the current tier
        if (tier.index > _currentTier.index) {
          setState(() {
            _currentTier = tier;
            _currentImage = imageProvider;
          });
        }
        
        // Remove from active lists
        final index = _activeListeners.indexOf(listener);
        if (index != -1) {
          _activeListeners.removeAt(index);
          _activeStreams.removeAt(index);
        }
        stream.removeListener(listener);

        if (syncCall) {
          print("ProgressiveImage onImage $tier $url"); Future.microtask(onLoaded);
        } else {
          onLoaded();
        }
      },
      onError: (exception, stackTrace) {
        if (!mounted || _loadSessionId != sessionId) return;
        
        final index = _activeListeners.indexOf(listener);
        if (index != -1) {
          _activeListeners.removeAt(index);
          _activeStreams.removeAt(index);
        }
        stream.removeListener(listener);

        // Tier failed to load, skip it and try the next if thumbnail wasn't yet set
        print("ProgressiveImage onImage $tier $url"); Future.microtask(onLoaded);
      },
    );
    
    _activeStreams.add(stream);
    _activeListeners.add(listener);
    stream.addListener(listener);
  }

  String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return ApiService.resolveMediaUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_currentImage != null) {
      content = Image(
        image: _currentImage!,
        fit: widget.fit,
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
      );
    } else {
      content =
          widget.errorWidget ??
          ShimmerPlaceholder(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            borderRadius: widget.borderRadius,
          );
    }

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: KeyedSubtree(key: ValueKey(_currentTier), child: content),
    );

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}
