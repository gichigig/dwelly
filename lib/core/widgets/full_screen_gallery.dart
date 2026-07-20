import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'shimmer_placeholder.dart';
import '../services/google_ad_service.dart';
import '../services/video_unlock_session_service.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class FullScreenGallery extends StatefulWidget {
  final int? rentalId;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final List<String> mediumUrls;
  final String? videoUrl;
  final int initialIndex;
  final bool showVideoFirst;
  final bool isPremium;

  const FullScreenGallery({
    super.key,
    this.rentalId,
    required this.imageUrls,
    this.thumbnailUrls = const [],
    this.mediumUrls = const [],
    this.videoUrl,
    this.initialIndex = 0,
    this.showVideoFirst = false,
    this.isPremium = false,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;
  VideoPlayerController? _videoController;
  bool _isPlaying = true;
  late bool _hasUnlockedVideo;

  @override
  void initState() {
    super.initState();
    _hasUnlockedVideo =
        widget.isPremium ||
        VideoUnlockSessionService.isVideoUnlocked(
          rentalId: widget.rentalId,
          videoUrl: widget.videoUrl,
        );
    _pageController = PageController(initialPage: widget.initialIndex);
    if (widget.videoUrl != null && _hasUnlockedVideo) {
      _initializeVideo();
    }
  }

  void _initializeVideo() {
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
          ..initialize().then((_) {
            _videoController!.setLooping(true);
            _videoController!.setVolume(0.0); // Mute by default
            _videoController!.play();
            if (mounted) setState(() {});
          });
  }

  Future<void> _unlockVideoWithAd() async {
    await GoogleRewardedAdManager.showRewardedAd(
      context,
      onReward: () {
        if (mounted) {
          VideoUnlockSessionService.unlockVideo(
            rentalId: widget.rentalId,
            videoUrl: widget.videoUrl,
          );
          setState(() => _hasUnlockedVideo = true);
          _initializeVideo();
        }
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  int get _itemCount =>
      widget.imageUrls.length + (widget.videoUrl != null ? 1 : 0);
  int get _videoIndex => widget.showVideoFirst ? 0 : widget.imageUrls.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: _itemCount,
        itemBuilder: (context, index) {
          if (widget.videoUrl != null && index == _videoIndex) {
            if (!_hasUnlockedVideo) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black87),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Colors.white54,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Watch Ad to Unlock Video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _unlockVideoWithAd,
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Unlock Video'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            if (_videoController != null &&
                _videoController!.value.isInitialized) {
              return Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                            _isPlaying = !_isPlaying;
                          });
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: _isPlaying
                              ? const SizedBox.shrink()
                              : const Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white54,
                                  size: 80,
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: FloatingActionButton.small(
                          backgroundColor: Colors.black54,
                          onPressed: () {
                            setState(() {
                              _videoController!.value.volume > 0
                                  ? _videoController!.setVolume(0)
                                  : _videoController!.setVolume(1);
                            });
                          },
                          child: Icon(
                            _videoController!.value.volume > 0
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(child: DwellyOrbitingLoader());
          }

          final imageIndex = (widget.videoUrl != null && index > _videoIndex)
              ? index - 1
              : (widget.videoUrl != null && index < _videoIndex)
              ? index
              : index;
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: DwellyNetworkImage(
                imageUrl: widget.imageUrls[imageIndex],
                thumbnailUrl: imageIndex < widget.thumbnailUrls.length
                    ? widget.thumbnailUrls[imageIndex]
                    : null,
                mediumUrl: imageIndex < widget.mediumUrls.length
                    ? widget.mediumUrls[imageIndex]
                    : null,
                loadFull: true,
                fit: BoxFit.contain,
                errorWidget: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
