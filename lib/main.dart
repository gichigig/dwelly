import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'core/services/auth_service.dart';
import 'core/services/app_notification_center.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/theme_service.dart';
import 'features/onboarding/location_onboarding_page.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(CrashReportingService.reportFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(CrashReportingService.reportUnhandled(error, stack));
        return true;
      };

      // Keep critical startup work minimal so first frame appears faster.
      final onboardingFuture = LocationOnboardingPage.isOnboardingComplete();
      await Future.wait([
        AuthService.init(),
        ThemeService.init(),
        AppNotificationCenter.init(),
      ]);
      final onboardingDone = await onboardingFuture;

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
          home: SplashScreen(
            child: onboardingComplete
                ? const AppShell()
                : LocationOnboardingPage(child: const AppShell()),
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
