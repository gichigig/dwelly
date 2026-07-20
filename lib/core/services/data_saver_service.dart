import 'package:shared_preferences/shared_preferences.dart';

class DataSaverService {
  DataSaverService._();
  static final DataSaverService instance = DataSaverService._();

  static const String _dataSaverKey = 'data_saver_enabled_v1';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dataSaverKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dataSaverKey, enabled);
  }
}
