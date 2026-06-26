import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final String? videoUrl;
  final int initialIndex;
  final bool showVideoFirst;

  const FullScreenGallery({
    super.key,
    required this.imageUrls,
    this.videoUrl,
    this.initialIndex = 0,
    this.showVideoFirst = false,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;
  VideoPlayerController? _videoController;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    if (widget.videoUrl != null) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
        ..initialize().then((_) {
          _videoController!.setLooping(true);
          _videoController!.play();
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  int get _itemCount => widget.imageUrls.length + (widget.videoUrl != null ? 1 : 0);
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
            if (_videoController != null && _videoController!.value.isInitialized) {
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
                              : const Icon(Icons.play_circle_fill, color: Colors.white54, size: 80),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final imageIndex = (widget.videoUrl != null && index > _videoIndex) ? index - 1 : (widget.videoUrl != null && index < _videoIndex) ? index : index;
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.imageUrls[imageIndex],
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
