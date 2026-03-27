import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app-wide theme mode with persistence.
class ThemeService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  late SharedPreferences _prefs;

  ThemeService._();

  static final ThemeService instance = ThemeService._();

  /// Initialize once at app start.
  static Future<void> init() async {
    instance._prefs = await SharedPreferences.getInstance();
    final saved = instance._prefs.getString(_themeModeKey);
    if (saved != null) {
      instance._mode = _stringToMode(saved);
    }
  }

  ThemeMode get mode => _mode;

  bool get isDarkMode => _mode == ThemeMode.dark;

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await _prefs.setString(_themeModeKey, _mode.name);
    notifyListeners();
  }

  static ThemeMode _stringToMode(String value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}
