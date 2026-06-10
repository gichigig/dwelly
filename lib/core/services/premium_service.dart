import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class PremiumService {
  static const String _locationFilterLastUsedKey =
      'premium_location_filter_last_used_date';

  static bool isPremiumActive() {
    return AuthService.currentUser?.isPremiumActive ?? false;
  }

  static Future<bool> canUseLocationFilter() async {
    if (isPremiumActive()) return true;

    final prefs = await SharedPreferences.getInstance();
    final lastUsed = prefs.getString(_locationFilterLastUsedKey);
    if (lastUsed == null || lastUsed.isEmpty) return true;

    return lastUsed != _todayKey();
  }

  static Future<void> recordLocationFilterUse() async {
    if (isPremiumActive()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationFilterLastUsedKey, _todayKey());
  }

  static Future<void> refreshPremiumStatus() async {
    await AuthService.refreshCurrentUser();
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
