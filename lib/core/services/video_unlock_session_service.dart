import 'auth_service.dart';

/// Tracks which property listing videos have been unlocked by the user during the current app session.
///
/// When a user watches a rewarded ad to unlock a listing's video, the unlock status
/// (`rentalId` and `videoUrl`) is stored in memory for the duration of the current app session.
/// The user can view the unlocked video across the listing detail page, full screen gallery,
/// or feed cards without being prompted to watch an ad again until the session is closed or reset.
class VideoUnlockSessionService {
  static final Set<int> _unlockedRentalIds = {};
  static final Set<String> _unlockedVideoUrls = {};

  VideoUnlockSessionService._();

  /// Check whether a property's video is unlocked for the current session.
  /// Returns `true` if:
  /// - The current user is an active Premium subscriber (`isPremiumActive == true`), OR
  /// - The property ID ([rentalId]) has been unlocked in this session, OR
  /// - The video URL ([videoUrl]) has been unlocked in this session.
  static bool isVideoUnlocked({int? rentalId, String? videoUrl}) {
    final isPremium = AuthService.currentUser?.isPremiumActive ?? false;
    if (isPremium) return true;
    if (rentalId != null && _unlockedRentalIds.contains(rentalId)) return true;
    if (videoUrl != null &&
        videoUrl.trim().isNotEmpty &&
        _unlockedVideoUrls.contains(videoUrl.trim())) {
      return true;
    }
    return false;
  }

  /// Mark a property's video as unlocked for the remainder of the session.
  static void unlockVideo({int? rentalId, String? videoUrl}) {
    if (rentalId != null) {
      _unlockedRentalIds.add(rentalId);
    }
    if (videoUrl != null && videoUrl.trim().isNotEmpty) {
      _unlockedVideoUrls.add(videoUrl.trim());
    }
  }

  /// Reset all session unlocks (for example when logging out or closing session).
  static void clearSession() {
    _unlockedRentalIds.clear();
    _unlockedVideoUrls.clear();
  }
}
