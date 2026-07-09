import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class PremiumService {
  static const String _locationFilterLastUsedKey =
      'premium_location_filter_last_used_date';

  /// Reactive notifier so widgets can listen for premium status changes
  /// (e.g., Google Ad widgets dispose loaded ads when premium activates).
  static final ValueNotifier<bool> premiumActive = ValueNotifier(false);

  /// Reactive notifier for whether the premium subscription page is enabled app-wide by super admin.
  static final ValueNotifier<bool> premiumPageEnabled = ValueNotifier(true);

  static bool isPremiumActive() {
    return AuthService.currentUser?.isPremiumActive ?? false;
  }

  static bool shouldHideAds() {
    if (AuthService.isTenantMode) return true;
    return AuthService.currentUser?.shouldHideAds ?? false;
  }

  /// Call whenever the current user changes (login, refresh, logout) so that
  /// listeners (ad widgets, etc.) react immediately.
  static void notifyPremiumStatusChanged() {
    final newValue = shouldHideAds();
    if (premiumActive.value != newValue) {
      premiumActive.value = newValue;
    }
  }

  static void notifyPremiumPageEnabled(bool enabled) {
    if (premiumPageEnabled.value != enabled) {
      premiumPageEnabled.value = enabled;
    }
  }

  static bool isPremiumPageVisible() {
    if (AuthService.isTenantMode) return false;
    return premiumPageEnabled.value;
  }

  static Future<bool> canUseLocationFilter() async {
    if (AuthService.isTenantMode) return true;
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
