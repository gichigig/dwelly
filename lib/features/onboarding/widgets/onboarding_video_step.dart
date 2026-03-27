import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class OnboardingVideoStep extends StatefulWidget {
  final String assetPath;
  final String message;
  final VoidCallback onTapContinue;
  final VoidCallback? onSkip;

  const OnboardingVideoStep({
    super.key,
    required this.assetPath,
    required this.message,
    required this.onTapContinue,
    this.onSkip,
  });

  @override
  State<OnboardingVideoStep> createState() => _OnboardingVideoStepState();
}

class _OnboardingVideoStepState extends State<OnboardingVideoStep> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final controller = VideoPlayerController.asset(widget.assetPath);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTapContinue,
          child: Stack(
            children: [
              Positioned.fill(child: _buildVideoLayer(colorScheme)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
              if (widget.onSkip != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: TextButton(
                    onPressed: widget.onSkip,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Skip'),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.58),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tap anywhere to continue',
                      style: TextStyle(
                        color: colorScheme.surfaceBright.withOpacity(0.95),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoLayer(ColorScheme colorScheme) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.play_circle_outline, size: 72, color: Colors.white70),
            SizedBox(height: 12),
            Text('Video unavailable', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_isLoading ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final controller = _controller!;
    final media = MediaQuery.of(context).size;
    final videoAspect = controller.value.aspectRatio <= 0
        ? 1.0
        : controller.value.aspectRatio;

    // Keep low-resolution tutorial videos crisp by avoiding aggressive stretch.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width * 0.9,
          maxHeight: media.height * 0.46,
          minWidth: 220,
          minHeight: 220 / videoAspect,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: videoAspect,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
