import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A custom Reddit-style orbiting loader widget for Dwelly.
/// Features the Dwelly 3D claymorphism logo gently bobbing/pulsing in the center
/// while a neon glowing satellite dot and gradient comet tail orbit around it.
class DwellyOrbitingLoader extends StatefulWidget {
  final double size;
  final Color glowColor;
  final bool showTrack;
  final String logoAsset;

  const DwellyOrbitingLoader({
    super.key,
    this.size = 64.0,
    this.glowColor = const Color(0xFF06B6D4), // Vibrant Cyan/Teal
    this.showTrack = true,
    this.logoAsset = 'assets/images/app_icon_dark.png',
  });

  @override
  State<DwellyOrbitingLoader> createState() => _DwellyOrbitingLoaderState();
}

class _DwellyOrbitingLoaderState extends State<DwellyOrbitingLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _orbitAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // 0.0 to 1.0 continuous rotation
    _orbitAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

    // Smooth breathing/bobbing pulse (0.92 -> 1.05 -> 0.92)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.92,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.05,
          end: 0.92,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Orbit Ring & Glowing Comet Tail
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _OrbitPainter(
                  progress: _orbitAnimation.value,
                  color: widget.glowColor,
                  showTrack: widget.showTrack,
                ),
              ),
              // Centered Pulsing Logo Emblem
              Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size * 0.62,
                  height: widget.size * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.glowColor.withValues(alpha: 0.25),
                        blurRadius: widget.size * 0.15,
                        spreadRadius: 1.0,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      widget.logoAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFF0F172A),
                        alignment: Alignment.center,
                        child: Text(
                          'D',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: widget.size * 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool showTrack;

  _OrbitPainter({
    required this.progress,
    required this.color,
    required this.showTrack,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width / 2) - (size.width * 0.08); // Slight padding from edge
    final dotRadius = math.max(3.0, size.width * 0.07);

    // 1. Draw subtle orbit track line
    if (showTrack) {
      final trackPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.025);
      canvas.drawCircle(center, radius, trackPaint);
    }

    // 2. Draw comet tail arc (trailing gradient arc behind the dot)
    final tailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.width * 0.04)
      ..strokeCap = StrokeCap.round;

    final currentAngle = progress * 2 * math.pi;
    const tailSweep = math.pi * 0.7; // ~126 degrees trail
    final startAngle = currentAngle - tailSweep;

    final rect = Rect.fromCircle(center: center, radius: radius);
    tailPaint.shader = SweepGradient(
      startAngle: startAngle,
      endAngle: currentAngle,
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.4),
        color,
      ],
      stops: const [0.0, 0.7, 1.0],
      transform: GradientRotation(startAngle),
    ).createShader(rect);

    canvas.drawArc(rect, startAngle, tailSweep, false, tailPaint);

    // 3. Draw glowing satellite dot at the leading head of the tail
    final dotCenter = Offset(
      center.dx + radius * math.cos(currentAngle),
      center.dy + radius * math.sin(currentAngle),
    );

    final glowRadius = dotRadius * 2.5;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.0)],
        stops: const [0.2, 1.0],
      ).createShader(Rect.fromCircle(center: dotCenter, radius: glowRadius));
    canvas.drawCircle(dotCenter, glowRadius, glowPaint);

    // Solid core dot
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotCenter, dotRadius * 0.7, corePaint);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.showTrack != showTrack;
  }
}
