import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app_shell.dart';
import 'core/services/auth_service.dart';
import 'core/services/ad_service.dart';
import 'core/services/app_notification_center.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/network_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/google_ad_service.dart';
import 'core/services/cache_service.dart';
import 'core/services/api_service.dart';
import 'core/services/deep_link_service.dart';
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
    if (state == AppLifecycleState.resumed) {
      NetworkService.instance.setAppForeground(true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      NetworkService.instance.setAppForeground(false);
    }
    // Disabled App Open ads (Google Ad Splash) as requested.
  }

  @override
  void didHaveMemoryPressure() {
    // When the OS signals low RAM, immediately purge all in-memory JSON/API maps and image caches!
    CacheManager.clearAll();
    ApiService.clearCachedGets();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = DwellyHttpOverrides();

      await Firebase.initializeApp().catchError((error, stack) {
        debugPrint('Firebase initialization warning: $error');
        throw error;
      });

      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      );

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(CrashReportingService.reportFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(CrashReportingService.reportUnhandled(error, stack));
        return true;
      };

      // Keep pre-runApp work strictly to local SharedPreferences (< 15ms)
      // so the native Android splash screen dismisses instantly.
      bool onboardingDone = false;
      try {
        await Future.wait([
          WelcomeOnboardingPage.isOnboardingComplete().then(
            (value) => onboardingDone = value,
          ),
          AuthService.init(),
          ThemeService.init(),
        ]).timeout(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('Startup init timeout/error (continuing to runApp): $e');
      }
      unawaited(OfflineQueueService.init());
      unawaited(AppNotificationCenter.init());
      unawaited(AdService.getInstance().then((svc) => svc.getDisplayConfig()));
      NetworkService.instance.initialize();

      runApp(
        ProviderScope(
          child: DwellyApp(
            onboardingComplete: onboardingDone,
            themeService: ThemeService.instance,
          ),
        ),
      );

      // Background sdk initializations after first frame
      unawaited(NotificationService.init());
      DeepLinkService.init();
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        unawaited(
          Future.delayed(const Duration(milliseconds: 3500), () {
            MobileAds.instance.initialize().then((_) {
              AppLifecycleReactor();
            });
          }),
        );
      }
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
          navigatorKey: NotificationService.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'IshinaDwelly',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeService.mode,
          builder: (context, child) {
            return NetworkBanner(child: child!);
          },
          home: onboardingComplete
              ? const AppShell()
              : WelcomeOnboardingPage(child: const AppShell()),
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
      textTheme: isDark
          ? ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            )
          : null,
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
