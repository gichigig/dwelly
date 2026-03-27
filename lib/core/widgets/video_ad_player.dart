import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/advertisement.dart';
import '../services/ad_service.dart';

/// Widget for playing video advertisements
class VideoAdPlayer extends StatefulWidget {
  final Advertisement ad;
  final AdService adService;
  final bool autoPlay;
  final bool showControls;
  final double? height;
  final BorderRadius? borderRadius;
  final VoidCallback? onFormTap;
  final VoidCallback? onComplete;

  const VideoAdPlayer({
    super.key,
    required this.ad,
    required this.adService,
    this.autoPlay = false,
    this.showControls = true,
    this.height,
    this.borderRadius,
    this.onFormTap,
    this.onComplete,
  });

  @override
  State<VideoAdPlayer> createState() => _VideoAdPlayerState();
}

class _VideoAdPlayerState extends State<VideoAdPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = true;
  bool _showThumbnail = true;
  bool _impressionRecorded = false;
  bool _viewRecorded = false;
  bool _completionRecorded = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _recordImpression();
  }

  void _recordImpression() {
    if (!_impressionRecorded) {
      _impressionRecorded = true;
      widget.adService.recordImpression(widget.ad.id);
    }
  }

  Future<void> _initializeVideo() async {
    if (widget.ad.videoUrl == null) return;

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.ad.videoUrl!),
    );

    try {
      await _controller!.initialize();
      await _controller!.setVolume(0);
      _controller!.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isMuted = true;
        });
        if (widget.autoPlay) {
          _play();
        }
      }
    } catch (e) {
      debugPrint('Video initialization error: $e');
    }
  }

  void _videoListener() {
    if (_controller == null) return;

    final value = _controller!.value;

    if (mounted) {
      setState(() {
        _isPlaying = value.isPlaying;
        if (value.duration.inMilliseconds > 0) {
          _progress =
              value.position.inMilliseconds / value.duration.inMilliseconds;
        }
      });
    }

    // Record video view when playback starts
    if (value.isPlaying && !_viewRecorded) {
      _viewRecorded = true;
      widget.adService.recordVideoView(widget.ad.id);
    }

    // Record completion when video ends
    if (value.position >= value.duration &&
        !_completionRecorded &&
        value.duration.inMilliseconds > 0) {
      _completionRecorded = true;
      widget.adService.recordVideoCompletion(widget.ad.id);
      widget.onComplete?.call();
    }
  }

  void _play() {
    _showThumbnail = false;
    _controller?.play();
    setState(() {});
  }

  void _pause() {
    _controller?.pause();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pause();
    } else {
      _play();
    }
  }

  Future<void> _toggleMute() async {
    if (_controller == null || !_isInitialized) return;

    final nextMuted = !_isMuted;
    await _controller!.setVolume(nextMuted ? 0 : 1);

    if (!mounted) return;
    setState(() {
      _isMuted = nextMuted;
    });
  }

  Future<void> _handleCtaTap() async {
    widget.adService.recordClick(widget.ad.id);

    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        if (widget.ad.targetUrl != null) {
          await _launchUrl(widget.ad.targetUrl!);
        }
        break;
      case LinkType.PLAYSTORE:
        if (widget.ad.playStoreUrl != null) {
          await _launchUrl(widget.ad.playStoreUrl!);
        }
        break;
      case LinkType.APPSTORE:
        if (widget.ad.appStoreUrl != null) {
          await _launchUrl(widget.ad.appStoreUrl!);
        }
        break;
      case LinkType.APP_BOTH:
        _showStoreSelector();
        break;
      case LinkType.FORM:
        widget.onFormTap?.call();
        break;
      case LinkType.NONE:
        break;
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showStoreSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Download App',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              if (widget.ad.playStoreUrl != null)
                ListTile(
                  leading: const Icon(
                    Icons.android,
                    size: 40,
                    color: Colors.green,
                  ),
                  title: const Text('Google Play Store'),
                  subtitle: const Text('For Android devices'),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUrl(widget.ad.playStoreUrl!);
                  },
                ),
              if (widget.ad.appStoreUrl != null)
                ListTile(
                  leading: const Icon(
                    Icons.apple,
                    size: 40,
                    color: Colors.grey,
                  ),
                  title: const Text('App Store'),
                  subtitle: const Text('For iOS devices'),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUrl(widget.ad.appStoreUrl!);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or thumbnail
            if (_showThumbnail && widget.ad.thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: widget.ad.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey[900]),
                errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
              )
            else if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),

            // Play button overlay (when showing thumbnail)
            if (_showThumbnail)
              Center(
                child: GestureDetector(
                  onTap: _isInitialized ? _play : null,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),

            // Controls overlay
            if (!_showThumbnail && widget.showControls)
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  color: Colors.transparent,
                  child: AnimatedOpacity(
                    opacity: !_isPlaying ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Progress bar
            if (!_showThumbnail)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
              ),

            // Bottom info bar
            Positioned(
              bottom: _showThumbnail ? 0 : 4,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                ),
                child: Row(
                  children: [
                    // Advertiser logo
                    if (widget.ad.advertiserLogoUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: widget.ad.advertiserLogoUrl!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    // Title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.ad.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.ad.advertiserName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // CTA button
                    if (widget.ad.linkType != LinkType.NONE)
                      GestureDetector(
                        onTap: _handleCtaTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getCtaText(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Ad label and verification badge
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'AD',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Verification badge (only for verified advertisers)
                  if (widget.ad.advertiserVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 12),
                          SizedBox(width: 2),
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
                ],
              ),
            ),

            // Mute toggle (video starts muted by default).
            if (_isInitialized)
              Positioned(
                top: widget.showControls ? 8 : 56,
                right: 8,
                child: GestureDetector(
                  onTap: _toggleMute,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getCtaText() {
    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        return 'Learn More';
      case LinkType.PLAYSTORE:
      case LinkType.APPSTORE:
      case LinkType.APP_BOTH:
        return 'Download';
      case LinkType.FORM:
        return 'Sign Up';
      case LinkType.NONE:
        return '';
    }
  }
}
