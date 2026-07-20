import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class AvatarCropperScreen extends StatefulWidget {
  final File imageFile;

  const AvatarCropperScreen({super.key, required this.imageFile});

  @override
  State<AvatarCropperScreen> createState() => _AvatarCropperScreenState();
}

class _AvatarCropperScreenState extends State<AvatarCropperScreen> {
  final TransformationController _controller = TransformationController();
  ui.Image? _originalImage;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  final double _circleRadius = 140.0;

  @override
  void initState() {
    super.initState();
    _loadImage(widget.imageFile);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      if (!mounted) return;
      setState(() {
        _originalImage = image;
        _isLoading = false;
      });

      // Center and scale image initially after frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resetAndCenter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load image for cropping: $e';
        _isLoading = false;
      });
    }
  }

  void _resetAndCenter() {
    if (_originalImage == null || !mounted) return;
    final size = MediaQuery.of(context).size;
    final layoutWidth = size.width;
    final layoutHeight = size.height - 160; // account for bottom bar & header

    final imgW = _originalImage!.width.toDouble();
    final imgH = _originalImage!.height.toDouble();

    // Scale so smaller dimension matches diameter of circle + some margin
    final circleDiameter = _circleRadius * 2;
    final scale = math.max(circleDiameter / imgW, circleDiameter / imgH) * 1.05;

    final tx = (layoutWidth - imgW * scale) / 2;
    final ty = (layoutHeight - imgH * scale) / 2;

    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  Future<void> _rotate90() async {
    if (_originalImage == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final oldImg = _originalImage!;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, oldImg.height.toDouble(), oldImg.width.toDouble()),
      );

      // Translate and rotate 90 degrees clockwise
      canvas.translate(oldImg.height.toDouble(), 0);
      canvas.rotate(math.pi / 2);
      canvas.drawImage(oldImg, Offset.zero, Paint());

      final picture = recorder.endRecording();
      final newImg = await picture.toImage(oldImg.height, oldImg.width);

      if (!mounted) return;
      setState(() {
        _originalImage = newImg;
        _isProcessing = false;
      });
      _resetAndCenter();
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cropAndCompress() async {
    if (_originalImage == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final size = MediaQuery.of(context).size;
      final layoutWidth = size.width;
      final layoutHeight = size.height - 160;

      final circleCenter = Offset(layoutWidth / 2, layoutHeight / 2);
      final screenCropRect = Rect.fromCircle(
        center: circleCenter,
        radius: _circleRadius,
      );

      final matrix = _controller.value;
      final tx = matrix.getTranslation().x;
      final ty = matrix.getTranslation().y;
      final s = matrix.getMaxScaleOnAxis();

      // Convert screen cutout bounds to source image pixel coordinates
      final srcLeft = (screenCropRect.left - tx) / s;
      final srcTop = (screenCropRect.top - ty) / s;
      final srcWidth = screenCropRect.width / s;
      final srcHeight = screenCropRect.height / s;
      final srcRect = Rect.fromLTWH(srcLeft, srcTop, srcWidth, srcHeight);

      // Output size: 512x512 crisp compressed profile image
      const outputSize = 512.0;
      final destRect = const Rect.fromLTWH(0, 0, outputSize, outputSize);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, destRect);

      // Draw high-res cropped region onto 512x512 destination canvas
      canvas.drawImageRect(
        _originalImage!,
        srcRect,
        destRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(
        outputSize.toInt(),
        outputSize.toInt(),
      );
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to encode cropped image bytes');
      }

      final tempDir = await getTemporaryDirectory();
      final targetFile = File(
        '${tempDir.path}/profile_avatar_cropped_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await targetFile.writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      Navigator.pop(context, targetFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Failed to crop photo: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.pop(context, null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                  const Text(
                    'Crop & Adjust Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.rotate_90_degrees_ccw,
                      color: Colors.white,
                    ),
                    tooltip: 'Rotate 90°',
                    onPressed: _isProcessing ? null : _rotate90,
                  ),
                ],
              ),
            ),

            // Main Crop Viewport
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: DwellyOrbitingLoader(glowColor: Colors.white),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final layoutSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        final circleCenter = Offset(
                          layoutSize.width / 2,
                          layoutSize.height / 2,
                        );

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // Interactive Image Viewport
                            InteractiveViewer(
                              transformationController: _controller,
                              minScale: 0.1,
                              maxScale: 10.0,
                              boundaryMargin: const EdgeInsets.all(800),
                              constrained: false,
                              child: RawImage(
                                image: _originalImage,
                                width: _originalImage!.width.toDouble(),
                                height: _originalImage!.height.toDouble(),
                                filterQuality: FilterQuality.high,
                              ),
                            ),

                            // Circular Cutout Overlay Mask
                            IgnorePointer(
                              child: CustomPaint(
                                size: layoutSize,
                                painter: _CircleCropOverlayPainter(
                                  center: circleCenter,
                                  radius: _circleRadius,
                                ),
                              ),
                            ),

                            // Helpful instruction banner
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: const Text(
                                    'Pinch to zoom & drag to fit inside the circle',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            if (_isProcessing)
                              Container(
                                color: Colors.black54,
                                child: const Center(
                                  child: DwellyOrbitingLoader(
                                    glowColor: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF161618),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _resetAndCenter,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _cropAndCompress,
                      icon: const Icon(Icons.check),
                      label: const Text(
                        'Apply & Upload',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleCropOverlayPainter extends CustomPainter {
  final Offset center;
  final double radius;

  _CircleCropOverlayPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    // Darken outer region outside circle
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final outerPath = Path()..addRect(rect);
    final innerPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final maskPath = Path.combine(
      PathOperation.difference,
      outerPath,
      innerPath,
    );

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );

    // Draw white circle border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleCropOverlayPainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.radius != radius;
  }
}
