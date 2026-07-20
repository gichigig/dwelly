import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PremiumMapAnimation extends StatefulWidget {
  final double size;

  const PremiumMapAnimation({super.key, this.size = 260});

  @override
  State<PremiumMapAnimation> createState() => _PremiumMapAnimationState();
}

class _PremiumMapAnimationState extends State<PremiumMapAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _MapAnimationPainter(t: _controller.value),
            );
          },
        ),
      ),
    );
  }
}

class _MapAnimationPainter extends CustomPainter {
  final double t; // 0.0 to 1.0

  const _MapAnimationPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Timeline calculations
    // 0.00 -> 0.12: Sweep rotate
    // 0.12 -> 0.40: Draw route line and moving dot
    // 0.40 -> 0.52: Zoom in
    // 0.52 -> 0.64: Show card
    // 0.64 -> 0.88: Hold card
    // 0.88 -> 1.00: Fade out / zoom out

    double rotation = 0.0;
    double scale = 1.0;
    double cardOpacity = 0.0;
    double dx = 0.0;
    double dy = 0.0;
    double lineProgress = 0.0;
    double movingDotProgress = 0.0;

    // Target dot coordinates relative to center
    final targetDx = size.width * 0.25;
    final targetDy = -size.height * 0.15;
    final targetAngle = math.atan2(targetDy, targetDx);

    if (t < 0.12) {
      // Sweeping from -pi to targetAngle
      final progress = t / 0.12;
      final curved = Curves.easeInOut.transform(progress);
      rotation = -math.pi + curved * (targetAngle + math.pi);
    } else if (t < 0.40) {
      // Locked, animate route and dot
      rotation = targetAngle;
      final progress = (t - 0.12) / 0.28;
      lineProgress = Curves.easeOut.transform((progress * 2).clamp(0.0, 1.0));
      movingDotProgress = Curves.easeInOut.transform(progress);
    } else if (t < 0.52) {
      // Zooming in
      rotation = targetAngle;
      lineProgress = 1.0;
      movingDotProgress = 1.0;
      final progress = (t - 0.40) / 0.12;
      final curved = Curves.easeInOut.transform(progress);
      scale = 1.0 + curved * 1.5; // Zoom up to 2.5x
      dx = -targetDx * curved;
      dy = -targetDy * curved;
    } else if (t < 0.64) {
      // Card fading in
      rotation = targetAngle;
      lineProgress = 1.0;
      movingDotProgress = 1.0;
      scale = 2.5;
      dx = -targetDx;
      dy = -targetDy;
      final progress = (t - 0.52) / 0.12;
      cardOpacity = progress;
    } else if (t < 0.88) {
      // Hold
      rotation = targetAngle;
      lineProgress = 1.0;
      movingDotProgress = 1.0;
      scale = 2.5;
      dx = -targetDx;
      dy = -targetDy;
      cardOpacity = 1.0;
    } else {
      // Fade out and reset
      final progress = (t - 0.88) / 0.12;
      final curved = Curves.easeInOut.transform(progress);
      rotation = targetAngle;
      scale = 2.5 - curved * 1.5;
      dx = -targetDx * (1 - curved);
      dy = -targetDy * (1 - curved);
      cardOpacity = 1.0 - progress;
      lineProgress = 1.0 - progress;
      lineProgress = 1.0 - progress;
      movingDotProgress = 1.0 - progress;
    }

    final routePath = Path()..moveTo(0, 0);
    // 1. Horizontal road right
    routePath.lineTo(targetDx * 0.4, 0);
    // 2. Vertical road down (90-degree turn)
    routePath.lineTo(targetDx * 0.4, targetDy * -0.5);
    // 3. Horizontal road right (90-degree turn)
    routePath.lineTo(targetDx * 0.6, targetDy * -0.5);
    // 4. Curved road swooping up to target
    routePath.quadraticBezierTo(
      targetDx,
      targetDy * -0.5, // Control point
      targetDx,
      targetDy, // End point
    );

    // Key points to place landmarks near
    final waypoints = [
      Offset(targetDx * 0.4, 0),
      Offset(targetDx * 0.4, targetDy * -0.5),
      Offset(targetDx * 0.6, targetDy * -0.5),
    ];

    final metrics = routePath.computeMetrics().first;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(dx, dy);

    // Draw Grid (Map Background)
    _drawGrid(canvas, size);

    // Draw dots
    _drawDots(canvas, size, targetDx, targetDy);

    // Draw Mock Landmarks along the path
    _drawLandmarks(canvas, size, waypoints);

    // Draw Cone (only visible before zoom gets extreme)
    if (scale < 2.0) {
      final coneOpacity = (1.0 - ((scale - 1.0) / 1.0)).clamp(0.0, 1.0);
      _drawCone(canvas, size, rotation, coneOpacity);
    }

    // Draw Route Line and Moving Dot
    if (lineProgress > 0.0) {
      final currentDistance = metrics.length * lineProgress;
      final currentPath = metrics.extractPath(0.0, currentDistance);

      final bounds = routePath.getBounds();
      final gradientRect = bounds.width > 0 && bounds.height > 0
          ? bounds
          : Rect.fromPoints(Offset.zero, const Offset(0.1, 0.1));

      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.blue.shade900, Colors.lightBlueAccent],
        ).createShader(gradientRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            5.0 /
            scale // Wider
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(currentPath, linePaint);

      if (movingDotProgress > 0.0) {
        final dotDistance = metrics.length * movingDotProgress;
        final tangent = metrics.getTangentForOffset(dotDistance);
        final movingDotPos = tangent?.position ?? Offset.zero;

        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.directions_walk.codePoint),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.0 / scale,
              fontFamily: Icons.directions_walk.fontFamily,
              package: Icons.directions_walk.fontPackage,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        iconPainter.layout();

        // Center the icon on the moving point
        iconPainter.paint(
          canvas,
          Offset(
            movingDotPos.dx - iconPainter.width / 2,
            movingDotPos.dy - iconPainter.height / 2,
          ),
        );
      }
    }

    // Draw center user dot
    final userDotPaint = Paint()..color = Colors.blue;
    canvas.drawCircle(Offset.zero, 6 / scale, userDotPaint);
    final userDotStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    canvas.drawCircle(Offset.zero, 6 / scale, userDotStroke);

    canvas.restore();

    // Draw popup card (drawn in static space, not scaled map space)
    if (cardOpacity > 0.0) {
      _drawPopupCard(canvas, size, cardOpacity);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.0;

    final step = size.width / 8;
    for (double i = -size.width; i <= size.width; i += step) {
      canvas.drawLine(Offset(i, -size.height), Offset(i, size.height), paint);
      canvas.drawLine(Offset(-size.width, i), Offset(size.width, i), paint);
    }
  }

  void _drawDots(Canvas canvas, Size size, double targetDx, double targetDy) {
    final dotPaint = Paint()..color = Colors.white.withOpacity(0.5);
    final targetPaint = Paint()
      ..color = Colors.blue
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    // Random but static coordinates for visual flavor
    final dots = [
      Offset(-size.width * 0.3, -size.height * 0.2),
      Offset(-size.width * 0.1, size.height * 0.3),
      Offset(size.width * 0.2, size.height * 0.4),
      Offset(size.width * 0.4, -size.height * 0.3),
      Offset(size.width * 0.15, -size.height * 0.4),
      Offset(-size.width * 0.4, size.height * 0.1),
    ];

    for (final dot in dots) {
      canvas.drawCircle(dot, 3, dotPaint);
    }

    // Target dot
    canvas.drawCircle(Offset(targetDx, targetDy), 5, targetPaint);
  }

  void _drawLandmarks(Canvas canvas, Size size, List<Offset> waypoints) {
    if (waypoints.length < 3) return;

    // Supermarket near first 90-degree turn
    _drawLandmark(
      canvas,
      waypoints[0] + const Offset(-10, -20),
      Icons.local_grocery_store,
      "Supermarket",
    );
    // City Park near second 90-degree turn
    _drawLandmark(
      canvas,
      waypoints[1] + const Offset(20, 10),
      Icons.park,
      "City Park",
    );
    // Cafe near start of the curve
    _drawLandmark(
      canvas,
      waypoints[2] + const Offset(15, -15),
      Icons.local_cafe,
      "Cafe",
    );
  }

  void _drawLandmark(Canvas canvas, Offset pos, IconData icon, String name) {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(pos.dx - iconPainter.width / 2, pos.dy - iconPainter.height / 2),
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        pos.dx - textPainter.width / 2,
        pos.dy + iconPainter.height / 2 + 2,
      ),
    );
  }

  void _drawCone(Canvas canvas, Size size, double angle, double opacity) {
    final conePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.blue.withOpacity(0.5 * opacity),
          Colors.blue.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: size.width))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);

    const fov = math.pi / 4; // 45 degrees
    final radius = size.width * 0.8;

    path.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      angle - fov / 2,
      fov,
      false,
    );
    path.lineTo(0, 0);

    canvas.drawPath(path, conePaint);

    // Draw cone edges
    final edgePaint = Paint()
      ..color = Colors.blue.withOpacity(0.8 * opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset.zero,
      Offset(
        math.cos(angle - fov / 2) * radius,
        math.sin(angle - fov / 2) * radius,
      ),
      edgePaint,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(
        math.cos(angle + fov / 2) * radius,
        math.sin(angle + fov / 2) * radius,
      ),
      edgePaint,
    );
  }

  void _drawPopupCard(Canvas canvas, Size size, double opacity) {
    final center = Offset(size.width / 2, size.height / 2);

    // Animate card sliding up
    final slideOffset = (1.0 - opacity) * 20;

    final cardWidth = size.width * 0.65;
    final cardHeight = size.height * 0.28;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - 30 + slideOffset),
        width: cardWidth,
        height: cardHeight,
      ),
      const Radius.circular(12),
    );

    // Shadow
    canvas.drawRRect(
      rect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withOpacity(0.4 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Card background
    canvas.drawRRect(rect, Paint()..color = Colors.white.withOpacity(opacity));

    // Details in card
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Price
    textPainter.text = TextSpan(
      text: '\$1,200/mo',
      style: TextStyle(
        color: Colors.black.withOpacity(opacity),
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(rect.left + 12, rect.top + 12));

    // Specs
    textPainter.text = TextSpan(
      text: '2 Bed • 2 Bath',
      style: TextStyle(
        color: Colors.grey.shade700.withOpacity(opacity),
        fontSize: 12,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(rect.left + 12, rect.top + 34));

    // Thumbnail placeholder
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.right - 44, rect.top + 10, 34, 34),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      thumbRect,
      Paint()..color = Colors.blue.withOpacity(0.2 * opacity),
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.home.codePoint),
        style: TextStyle(
          color: Colors.blue.withOpacity(opacity),
          fontSize: 20,
          fontFamily: Icons.home.fontFamily,
          package: Icons.home.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, Offset(thumbRect.left + 7, thumbRect.top + 7));
  }

  @override
  bool shouldRepaint(covariant _MapAnimationPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}
