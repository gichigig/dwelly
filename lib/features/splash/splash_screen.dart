import 'dart:async';
import 'package:flutter/material.dart';
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
  static const Duration _minimumSplashDuration = Duration(milliseconds: 900);
  static const Duration _maxAdWait = Duration(milliseconds: 1200);

  bool _showSplash = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late final Future<_SplashAdPayload?> _splashAdFuture;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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

    _splashTimer = Timer(_minimumSplashDuration, () async {
      await _finishSplashFlow();
    });
  }

  Future<_SplashAdPayload?> _preloadSplashAd() async {
    try {
      final adService = await AdService.getInstance();
      final splashAd = await adService.getTargetedAd(AdPlacement.SPLASH);
      if (splashAd == null) return null;
      return _SplashAdPayload(adService: adService, ad: splashAd);
    } catch (_) {
      return null;
    }
  }

  Future<void> _finishSplashFlow() async {
    if (!mounted) return;

    try {
      final payload = await _splashAdFuture.timeout(
        _maxAdWait,
        onTimeout: () => null,
      );

      if (mounted && payload != null) {
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
      }
    } catch (_) {
      // Fail open: continue into app if splash ad fails.
    } finally {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
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
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0EA5E9).withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback if image not found - show the D logo programmatically
                      return _buildFallbackLogo();
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // App Name
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFF0EA5E9), // Teal
                    Color(0xFF1E40AF), // Blue
                  ],
                ).createShader(bounds),
                child: const Text(
                  'Dwelly',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Real Estate App',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 60),

              // By Bluvberry
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final byBluvberryOpacity = Tween<double>(begin: 0.0, end: 1.0)
                      .animate(
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
                        fontSize: 14,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFF6366F1), // Indigo
                          Color(0xFF8B5CF6), // Purple
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        'bluvberry',
                        style: TextStyle(
                          fontSize: 18,
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
    );
  }

  Widget _buildFallbackLogo() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: CustomPaint(painter: DwellyLogoPainter()),
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
