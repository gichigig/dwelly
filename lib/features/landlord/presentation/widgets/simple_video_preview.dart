import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class SimpleVideoPreview extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onRemove;

  const SimpleVideoPreview({
    Key? key,
    required this.videoUrl,
    required this.onRemove,
  }) : super(key: key);

  @override
  State<SimpleVideoPreview> createState() => _SimpleVideoPreviewState();
}

class _SimpleVideoPreviewState extends State<SimpleVideoPreview> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() {
                _isInitialized = true;
              });
            }
          })
          .catchError((e) {
            debugPrint('Error initializing video: $e');
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const DwellyOrbitingLoader(glowColor: Colors.white),

          // Play/Pause overlay
          if (_isInitialized)
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
              child: Container(
                color: Colors.transparent, // Capture taps over the video
                alignment: Alignment.center,
                child: Icon(
                  _controller.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 50,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ),

          // Remove button
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: widget.onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
