import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app_shell.dart';
import 'core/services/auth_service.dart';
import 'core/services/app_notification_center.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/network_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/google_ad_service.dart';
import 'core/widgets/network_banner.dart';
import 'features/onboarding/welcome_onboarding_page.dart';
import 'features/splash/splash_screen.dart';

class DwellyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 5);
  }
}

class AppLifecycleReactor extends WidgetsBindingObserver {
  DateTime? _backgroundTime;
  
  AppLifecycleReactor() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _backgroundTime ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundTime != null) {
        final backgroundDuration = DateTime.now().difference(_backgroundTime!);
        // Only show App Open Ad if the app was in the background for more than 15 seconds.
        // This prevents the ad from overriding the screen during micro-interruptions 
        // like pulling down the notification tray, toggling Wi-Fi, or system dialogs.
        if (backgroundDuration.inSeconds > 15) {
          AppOpenAdManager.instance.showAdIfAvailable();
        }
        _backgroundTime = null;
      }
    }
  }
}

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = DwellyHttpOverrides();

      await Firebase.initializeApp();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(CrashReportingService.reportFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(CrashReportingService.reportUnhandled(error, stack));
        return true;
      };

      // Keep critical startup work minimal so first frame appears faster.
      final onboardingFuture = WelcomeOnboardingPage.isOnboardingComplete();
      await Future.wait([
        AuthService.init(),
        ThemeService.init(),
        AppNotificationCenter.init(),
      ]);
      unawaited(OfflineQueueService.init());
      AppLifecycleReactor? lifecycleReactor;
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        unawaited(MobileAds.instance.initialize().then((_) {
          AppOpenAdManager.instance.loadAd();
          lifecycleReactor = AppLifecycleReactor();
        }));
      }
      final onboardingDone = await onboardingFuture;

      NetworkService.instance.initialize();

      runApp(
        DwellyApp(
          onboardingComplete: onboardingDone,
          themeService: ThemeService.instance,
        ),
      );

      // Notification setup can continue in background.
      unawaited(NotificationService.init());
    },
    (error, stack) {
      unawaited(CrashReportingService.reportUnhandled(error, stack));
    },
  );
}

class DwellyApp extends StatelessWidget {
  final bool onboardingComplete;
  final ThemeService themeService;

  const DwellyApp({
    super.key,
    required this.onboardingComplete,
    required this.themeService,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        final lightTheme = _buildTheme(Brightness.light);
        final darkTheme = _buildTheme(Brightness.dark);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dwelly',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeService.mode,
          builder: (context, child) {
            return NetworkBanner(child: child!);
          },
          home: SplashScreen(
            child: onboardingComplete
                ? const AppShell()
                : WelcomeOnboardingPage(child: const AppShell()),
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0EA5E9),
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final fieldFill = isDark
        ? colorScheme.surfaceContainerHighest.withOpacity(0.55)
        : colorScheme.surfaceContainerHighest.withOpacity(0.4);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.85),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
