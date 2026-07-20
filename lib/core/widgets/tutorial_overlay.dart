import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single step in the tutorial spotlight sequence.
class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
  });
}

/// Controller that manages the tutorial overlay lifecycle.
///
/// Call [start] with a list of [TutorialStep]s after the first frame renders.
/// The overlay is shown only once per user (persisted via SharedPreferences).
class TutorialOverlayController {
  static const _prefKey = 'explore_tutorial_completed';

  OverlayEntry? _overlayEntry;
  final BuildContext _context;
  final VoidCallback? onDismissed;

  TutorialOverlayController(this._context, {this.onDismissed});

  /// Shows the tutorial if the user hasn't completed it yet.
  Future<void> start(List<TutorialStep> steps) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyDone = prefs.getBool(_prefKey) == true;
    print('[Tutorial] SharedPreferences "$_prefKey" = $alreadyDone');

    if (alreadyDone) {
      print('[Tutorial] Tutorial already completed — skipping');
      onDismissed?.call();
      return;
    }

    // Small delay so the page fully settles (location loading, etc.)
    await Future.delayed(const Duration(milliseconds: 800));

    if (!_context.mounted) {
      print('[Tutorial] Context is no longer mounted after delay — aborting');
      return;
    }

    print('[Tutorial] Inserting overlay with ${steps.length} steps');
    _overlayEntry = OverlayEntry(
      builder: (_) => _TutorialOverlayWidget(
        steps: steps,
        onComplete: () => _dismiss(prefs),
        onSkip: () => _dismiss(prefs),
      ),
    );

    Overlay.of(_context).insert(_overlayEntry!);
    print('[Tutorial] Overlay inserted successfully');
  }

  void _dismiss(SharedPreferences prefs) {
    final entry = _overlayEntry;
    _overlayEntry = null;
    prefs.setBool(_prefKey, true);
    if (entry != null) {
      try {
        entry.remove();
      } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          entry.remove();
        } catch (_) {}
      });
    }
    onDismissed?.call();
  }

  /// Resets the tutorial so it shows again next time.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay Widget
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialOverlayWidget extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const _TutorialOverlayWidget({
    required this.steps,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<_TutorialOverlayWidget> createState() => _TutorialOverlayWidgetState();
}

class _TutorialOverlayWidgetState extends State<_TutorialOverlayWidget>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  Timer? _autoAdvanceTimer;
  bool _isDismissing = false;

  // Spotlight position & size (animated)
  late AnimationController _spotlightController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  Rect? _targetRect;
  Rect? _previousRect;

  @override
  void initState() {
    super.initState();

    _spotlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Kick off after the current frame finishes layout so renderBox keys aren't null!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _goToStep(0);
        _fadeController.forward();
      }
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _spotlightController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    print('[Tutorial] _goToStep($index) — total steps: ${widget.steps.length}');
    if (index >= widget.steps.length) {
      print('[Tutorial] All steps done — dismissing');
      _dismissOverlay(widget.onComplete);
      return;
    }

    _autoAdvanceTimer?.cancel();

    final step = widget.steps[index];
    final renderBox =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null || !renderBox.attached) {
      print(
        '[Tutorial] Step $index ("${step.title}") — renderBox is ${renderBox == null ? "null" : "detached"}, skipping',
      );
      Future.microtask(() => _goToStep(index + 1));
      return;
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final newRect = Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );

    print('[Tutorial] Step $index ("${step.title}") — rect: $newRect');

    setState(() {
      _previousRect = _targetRect;
      _targetRect = newRect;
      _currentStep = index;
    });

    _spotlightController.forward(from: 0);

    // Auto-advance after 3 seconds
    _autoAdvanceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _goToStep(_currentStep + 1);
    });
  }

  void _onTap() {
    _autoAdvanceTimer?.cancel();
    _goToStep(_currentStep + 1);
  }

  void _dismissOverlay(VoidCallback callback) {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoAdvanceTimer?.cancel();

    var done = false;
    void finish() {
      if (done) return;
      done = true;
      callback();
    }

    if (_fadeController.value <= 0.05) {
      finish();
      return;
    }

    _fadeController.reverse().whenComplete(finish);
    Future.delayed(const Duration(milliseconds: 200), finish);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Blurred + dark background with spotlight cutout
              AnimatedBuilder(
                animation: Listenable.merge([
                  _spotlightController,
                  _pulseAnimation,
                ]),
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(
                    _spotlightController.value,
                  );
                  final currentRect = _targetRect;
                  final prevRect = _previousRect ?? _targetRect;

                  if (currentRect == null) {
                    return const SizedBox.expand();
                  }

                  // Interpolate rect position
                  final animatedRect = prevRect != null
                      ? Rect.lerp(prevRect, currentRect, t)!
                      : currentRect;

                  // Calculate spotlight circle
                  final center = animatedRect.center;
                  final baseRadius = (animatedRect.longestSide / 2) + 20;
                  final radius = baseRadius + _pulseAnimation.value;

                  return SizedBox.expand(
                    child: CustomPaint(
                      painter: _HolePainter(center, radius),
                    ),
                  );
                },
              ),

              // Spotlight ring glow
              AnimatedBuilder(
                animation: Listenable.merge([
                  _spotlightController,
                  _pulseAnimation,
                ]),
                builder: (context, _) {
                  if (_targetRect == null) return const SizedBox.shrink();

                  final t = Curves.easeOutCubic.transform(
                    _spotlightController.value,
                  );
                  final prevRect = _previousRect ?? _targetRect;
                  final animatedRect = Rect.lerp(prevRect, _targetRect!, t)!;
                  final center = animatedRect.center;
                  final baseRadius = (animatedRect.longestSide / 2) + 20;
                  final radius = baseRadius + _pulseAnimation.value;

                  return Positioned(
                    left: center.dx - radius - 4,
                    top: center.dy - radius - 4,
                    child: IgnorePointer(
                      child: Container(
                        width: (radius + 4) * 2,
                        height: (radius + 4) * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: 0.4 + 0.2 * (_pulseAnimation.value / 12),
                            ),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.15),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Instructional card
              AnimatedBuilder(
                animation: _spotlightController,
                builder: (context, _) {
                  if (_targetRect == null ||
                      _currentStep >= widget.steps.length) {
                    return const SizedBox.shrink();
                  }

                  final step = widget.steps[_currentStep];
                  final t = Curves.easeOutCubic.transform(
                    _spotlightController.value,
                  );
                  final prevRect = _previousRect ?? _targetRect;
                  final animatedRect = Rect.lerp(prevRect, _targetRect!, t)!;

                  // Position card below or above the spotlight
                  final spotBottom =
                      animatedRect.bottom + (animatedRect.longestSide / 2) + 40;
                  final showBelow = spotBottom + 160 < screenSize.height;

                  final cardTop = showBelow ? animatedRect.bottom + 40 : null;
                  final cardBottom = showBelow
                      ? null
                      : screenSize.height - animatedRect.top + 40;

                  return Positioned(
                    left: 24,
                    right: 24,
                    top: cardTop,
                    bottom: cardBottom,
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - t)),
                        child: _buildInstructionCard(step, context),
                      ),
                    ),
                  );
                },
              ),

              // Finish button (top right)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: TextButton.icon(
                  onPressed: () => _dismissOverlay(widget.onComplete),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Finish'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),

              // Step counter (bottom)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.steps.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _currentStep ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _currentStep
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionCard(TutorialStep step, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon + Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(step.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                step.description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              // Buttons row: Finish and Next
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _dismissOverlay(widget.onComplete),
                    icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
                    label: const Text(
                      'Finish',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (_currentStep < widget.steps.length - 1)
                    ElevatedButton.icon(
                      onPressed: _onTap,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Next'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _dismissOverlay(widget.onComplete),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Tap hint
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Tap anywhere outside or click Finish to exit',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inverted Circle Clipper — clips everything EXCEPT the circle
// ─────────────────────────────────────────────────────────────────────────────

class _HolePainter extends CustomPainter {
  final Offset center;
  final double radius;

  _HolePainter(this.center, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    // A massive stroke width ensures the entire screen is covered with color,
    // leaving only the center 'radius' perfectly transparent.
    // This is vastly more performant than using ClipPath with evenOdd fill.
    final maxDimension = size.width > size.height ? size.width : size.height;
    final strokeWidth = maxDimension * 2.5;

    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius + (strokeWidth / 2), paint);
  }

  @override
  bool shouldRepaint(_HolePainter oldDelegate) {
    return center != oldDelegate.center || radius != oldDelegate.radius;
  }
}
