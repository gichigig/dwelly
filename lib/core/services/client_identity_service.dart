import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ClientIdentityService {
  static const String _clientIdKey = 'anonymous_client_id';
  static const Uuid _uuid = Uuid();
  static String? _cachedClientId;

  static Future<String> getClientId() async {
    if (_cachedClientId != null && _cachedClientId!.isNotEmpty) {
      return _cachedClientId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_clientIdKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedClientId = existing;
      return existing;
    }

    final generated = _uuid.v4();
    await prefs.setString(_clientIdKey, generated);
    _cachedClientId = generated;
    return generated;
  }
}
