import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OnboardingMotionType { search, filter, scroll }

class OnboardingMotionStep extends StatefulWidget {
  final OnboardingMotionType type;
  final String message;
  final VoidCallback onFinished;
  final VoidCallback? onSkip;
  final Duration duration;
  final bool forceStaticFallback;

  const OnboardingMotionStep({
    super.key,
    required this.type,
    required this.message,
    required this.onFinished,
    this.onSkip,
    this.duration = const Duration(seconds: 3),
    this.forceStaticFallback = false,
  });

  @override
  State<OnboardingMotionStep> createState() => _OnboardingMotionStepState();
}

class _OnboardingMotionStepState extends State<OnboardingMotionStep> {
  Timer? _finishTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _finishTimer = Timer(widget.duration, _completeStep);
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    super.dispose();
  }

  void _completeStep() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.18),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 420,
                    maxHeight: 280,
                    minWidth: 220,
                    minHeight: 180,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: OnboardingMotionScene(
                        type: widget.type,
                        forceStaticFallback: widget.forceStaticFallback,
                      ),
                    ),
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
              bottom: 28,
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
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
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
                    'Continuing automatically...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
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

class OnboardingMotionScene extends StatefulWidget {
  final OnboardingMotionType type;
  final bool forceStaticFallback;

  const OnboardingMotionScene({
    super.key,
    required this.type,
    this.forceStaticFallback = false,
  });

  @override
  State<OnboardingMotionScene> createState() => _OnboardingMotionSceneState();
}

class _OnboardingMotionSceneState extends State<OnboardingMotionScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.forceStaticFallback) {
      return _StaticSceneFallback(type: widget.type);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _MotionScenePainter(
            type: widget.type,
            t: _controller.value,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _MotionScenePainter extends CustomPainter {
  final OnboardingMotionType type;
  final double t;
  final ColorScheme colorScheme;

  const _MotionScenePainter({
    required this.type,
    required this.t,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surfaceContainerHighest,
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    switch (type) {
      case OnboardingMotionType.search:
        _paintSearchScene(canvas, size);
      case OnboardingMotionType.filter:
        _paintFilterScene(canvas, size);
      case OnboardingMotionType.scroll:
        _paintScrollScene(canvas, size);
    }
  }

  void _paintSearchScene(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.48, size.height * 0.52);
    final pulse = 0.7 + 0.3 * math.sin(t * math.pi * 2);
    final baseRadius = math.min(size.width, size.height) * 0.18;

    final mapRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    mapRing.color = colorScheme.primary.withValues(alpha: 0.24);
    canvas.drawCircle(center, baseRadius * 1.1, mapRing);
    mapRing.color = colorScheme.primary.withValues(alpha: 0.16);
    canvas.drawCircle(center, baseRadius * 1.45, mapRing);

    final pinPaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.fill;
    final pinTop = Offset(center.dx, center.dy - baseRadius * 0.6);
    canvas.drawCircle(pinTop, baseRadius * 0.38, pinPaint);

    final pinTailPath = Path()
      ..moveTo(pinTop.dx, pinTop.dy + baseRadius * 0.78)
      ..lineTo(pinTop.dx - baseRadius * 0.24, pinTop.dy + baseRadius * 0.2)
      ..lineTo(pinTop.dx + baseRadius * 0.24, pinTop.dy + baseRadius * 0.2)
      ..close();
    canvas.drawPath(pinTailPath, pinPaint);

    canvas.drawCircle(
      pinTop,
      baseRadius * 0.15,
      Paint()..color = colorScheme.onPrimary,
    );

    final pulsePaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.15 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(pinTop, baseRadius * (0.4 + 0.2 * pulse), pulsePaint);

    final sweepX = size.width * (0.18 + 0.62 * t);
    final glassCenter = Offset(sweepX, size.height * 0.74);
    final magnifierPaint = Paint()
      ..color = colorScheme.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(glassCenter, baseRadius * 0.32, magnifierPaint);
    canvas.drawLine(
      glassCenter + Offset(baseRadius * 0.22, baseRadius * 0.22),
      glassCenter + Offset(baseRadius * 0.46, baseRadius * 0.46),
      magnifierPaint,
    );
  }

  void _paintFilterScene(Canvas canvas, Size size) {
    final cardWidth = size.width * 0.72;
    final cardHeight = size.height * 0.15;
    final startX = (size.width - cardWidth) / 2;
    final topY = size.height * 0.2;
    final spacing = cardHeight * 0.38;

    final cardPaint = Paint()
      ..color = colorScheme.surface
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (int i = 0; i < 3; i++) {
      final y = topY + i * (cardHeight + spacing);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(startX, y, cardWidth, cardHeight),
        const Radius.circular(12),
      );
      canvas.drawRRect(rrect, cardPaint);
      canvas.drawRRect(rrect, borderPaint);
    }

    final sweep = Curves.easeInOut.transform((t + 0.1) % 1);
    final chipX = startX + cardWidth * (0.22 + 0.56 * sweep);
    final chipY = topY + cardHeight * 0.26;
    final chipW = cardWidth * (0.34 - 0.1 * sweep);
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chipX, chipY, chipW, cardHeight * 0.5),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      chipRect,
      Paint()..color = colorScheme.primaryContainer.withValues(alpha: 0.95),
    );

    final funnelPath = Path()
      ..moveTo(size.width * 0.16, size.height * 0.18)
      ..lineTo(size.width * 0.34, size.height * 0.18)
      ..lineTo(size.width * 0.24, size.height * 0.28)
      ..lineTo(size.width * 0.24, size.height * 0.36)
      ..lineTo(size.width * 0.2, size.height * 0.39)
      ..lineTo(size.width * 0.2, size.height * 0.28)
      ..close();
    canvas.save();
    canvas.translate(size.width * 0.3 * sweep, 0);
    canvas.drawPath(
      funnelPath,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.9),
    );
    canvas.restore();

    final textPainter = TextPainter(
      text: TextSpan(
        text: '1 Bedroom',
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: chipW - 10);
    textPainter.paint(
      canvas,
      Offset(
        chipRect.left + (chipW - textPainter.width) / 2,
        chipRect.top + (chipRect.height - textPainter.height) / 2,
      ),
    );
  }

  void _paintScrollScene(Canvas canvas, Size size) {
    final width = size.width * 0.68;
    final height = size.height * 0.2;
    final x = (size.width - width) / 2;
    final yBase = size.height * 0.2;
    final travel = size.height * 0.44;

    for (int i = 0; i < 3; i++) {
      final localT = (t + (i * 0.24)) % 1;
      final y = yBase + (localT * travel);
      final alpha = (1 - (localT * 0.75)).clamp(0.18, 1.0);
      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(14),
      );
      canvas.drawRRect(
        cardRect,
        Paint()..color = colorScheme.surface.withValues(alpha: alpha),
      );
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final arrowCenter = Offset(size.width * 0.83, size.height * 0.74);
    final arrowOffset = 6 * math.sin(t * math.pi * 2);
    final arrowPath = Path()
      ..moveTo(arrowCenter.dx, arrowCenter.dy - 14 + arrowOffset)
      ..lineTo(arrowCenter.dx - 10, arrowCenter.dy - 2 + arrowOffset)
      ..lineTo(arrowCenter.dx + 10, arrowCenter.dy - 2 + arrowOffset)
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.92),
    );
    canvas.drawLine(
      Offset(arrowCenter.dx, arrowCenter.dy - 2 + arrowOffset),
      Offset(arrowCenter.dx, arrowCenter.dy + 18 + arrowOffset),
      Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.92)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MotionScenePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.type != type ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _StaticSceneFallback extends StatelessWidget {
  final OnboardingMotionType type;

  const _StaticSceneFallback({required this.type});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (IconData icon, String label) = switch (type) {
      OnboardingMotionType.search => (Icons.search_rounded, 'Search nearby'),
      OnboardingMotionType.filter => (Icons.tune_rounded, 'Filter quickly'),
      OnboardingMotionType.scroll => (
        Icons.swipe_vertical_rounded,
        'Scroll listings',
      ),
    };

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
