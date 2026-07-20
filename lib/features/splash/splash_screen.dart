import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/models/advertisement.dart';
import '../../core/services/ad_service.dart';
import '../../core/widgets/app_launch_ad_screen.dart';

class _SplashAdPayload {
  final AdService adService;
  final Advertisement ad;

  const _SplashAdPayload({required this.adService, required this.ad});
}

class SplashScreen extends StatefulWidget {
  final Widget child;

  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _showSplash = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late final Future<_SplashAdPayload?> _splashAdFuture;
  bool _splashFlowStarted = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Splash] initState called');

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();
    _splashAdFuture = _preloadSplashAd();

    // Wait for the first real frame to be rendered, THEN start a wall-clock
    // timer for the minimum splash duration.  This guarantees the user sees the
    // splash for at least 1.5 s of *real screen time* (not jank time).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[Splash] First frame rendered — starting splash timer');
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 1500), () {
        debugPrint('[Splash] Splash timer fired — finishing splash flow');
        _finishSplashFlow();
      });
    });
  }

  Future<_SplashAdPayload?> _preloadSplashAd() async {
    try {
      final adService = await AdService.getInstance().timeout(
        const Duration(milliseconds: 800),
      );
      final splashAd = await adService
          .getTargetedAd(AdPlacement.SPLASH)
          .timeout(const Duration(milliseconds: 800));
      if (splashAd == null) {
        debugPrint('[Splash] No splash ad available');
        return null;
      }
      debugPrint('[Splash] Splash ad preloaded: ${splashAd.id}');
      return _SplashAdPayload(adService: adService, ad: splashAd);
    } catch (e) {
      debugPrint('[Splash] Splash ad preload failed: $e');
      return null;
    }
  }

  Future<void> _finishSplashFlow() async {
    if (!mounted || _splashFlowStarted) return;
    _splashFlowStarted = true;
    debugPrint('[Splash] _finishSplashFlow started');

    try {
      final payload = await _splashAdFuture.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {
          debugPrint('[Splash] Splash ad future timed out');
          return null;
        },
      );

      debugPrint(
        '[Splash] Splash ad payload: ${payload != null ? 'available' : 'null'}',
      );

      if (mounted && payload != null) {
        debugPrint('[Splash] Showing splash ad screen');
        await Navigator.of(context).push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, _, __) => AppLaunchAdScreen(
              ad: payload.ad,
              adService: payload.adService,
              placement: AdPlacement.SPLASH,
              markLaunchAdShownOnComplete: false,
              onComplete: () => Navigator.of(context).pop(),
            ),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
        debugPrint('[Splash] Splash ad screen dismissed');
      }
    } catch (e) {
      debugPrint('[Splash] Error in splash flow: $e');
      // Fail open: continue into app if splash ad fails.
    } finally {
      if (mounted) {
        debugPrint('[Splash] Dismissing splash — showing app');
        setState(() {
          _showSplash = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) {
      return widget.child;
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Centered Logo and Name
                SafeArea(
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Small Logo
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF0EA5E9,
                                      ).withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    'assets/images/app_icon_dark.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/logo.png',
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.transparent,
                                                child: CustomPaint(
                                                  painter: DwellyLogoPainter(),
                                                ),
                                              );
                                            },
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // App Name
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFF0EA5E9), // Teal
                                        Color(0xFF1E40AF), // Blue
                                      ],
                                    ).createShader(bounds),
                                child: const Text(
                                  'Dwelly',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Tagline
                          Text(
                            'Real Estate App',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // By Bluvberry
                          AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              final byBluvberryOpacity =
                                  Tween<double>(begin: 0.0, end: 1.0).animate(
                                    CurvedAnimation(
                                      parent: _animationController,
                                      curve: const Interval(
                                        0.5,
                                        1.0,
                                        curve: Curves.easeOut,
                                      ),
                                    ),
                                  );
                              return Opacity(
                                opacity: byBluvberryOpacity.value,
                                child: child,
                              );
                            },
                            child: Column(
                              children: [
                                Text(
                                  'by',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          Color(0xFF6366F1), // Indigo
                                          Color(0xFF8B5CF6), // Purple
                                        ],
                                      ).createShader(bounds),
                                  child: const Text(
                                    'bluvberry',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class DwellyLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    // Gradient for the D shape
    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF0EA5E9), // Teal
        Color(0xFF1E40AF), // Blue
      ],
    );

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    paint.shader = gradient.createShader(rect);

    // Draw the D outline
    final path = Path();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width * 0.35;

    // D shape - vertical line
    path.moveTo(centerX - radius * 0.5, centerY - radius);
    path.lineTo(centerX - radius * 0.5, centerY + radius);

    // D shape - curve
    path.moveTo(centerX - radius * 0.5, centerY - radius);
    path.quadraticBezierTo(
      centerX + radius,
      centerY,
      centerX - radius * 0.5,
      centerY + radius,
    );

    canvas.drawPath(path, paint);

    // Draw house roof
    final roofPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);

    final roofPath = Path();
    roofPath.moveTo(centerX - radius * 0.6, centerY);
    roofPath.lineTo(centerX - radius * 0.1, centerY - radius * 0.5);
    roofPath.lineTo(centerX + radius * 0.3, centerY);

    canvas.drawPath(roofPath, roofPaint);

    // Draw window (small square)
    final windowPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = gradient.createShader(rect);

    final windowSize = radius * 0.25;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX - radius * 0.1, centerY + radius * 0.15),
        width: windowSize,
        height: windowSize,
      ),
      windowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
