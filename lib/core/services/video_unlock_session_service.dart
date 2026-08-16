import 'auth_service.dart';

/// Tracks which property listing videos have been unlocked by the user during the current app session.
/// All property videos are automatically unlocked for all users without requiring ads.
class VideoUnlockSessionService {
  VideoUnlockSessionService._();

  /// Check whether a property's video is unlocked for the current session.
  /// Always returns `true` so all listing videos play directly without requiring ad unlocks.
  static bool isVideoUnlocked({int? rentalId, String? videoUrl}) {
    return true;
  }

  /// Mark a property's video as unlocked for the remainder of the session.
  static void unlockVideo({int? rentalId, String? videoUrl}) {}

  /// Reset all session unlocks.
  static void clearSession() {}
}
