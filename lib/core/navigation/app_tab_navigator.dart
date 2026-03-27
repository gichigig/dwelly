import 'package:flutter/foundation.dart';

/// Lightweight tab navigation bridge used by child screens to request
/// switching tabs on the root [AppShell].
class AppTabNavigator {
  AppTabNavigator._();

  static final ValueNotifier<int?> _requestedTab = ValueNotifier<int?>(null);

  static ValueListenable<int?> get requestedTab => _requestedTab;

  static void openTab(int index) {
    _requestedTab.value = index;
  }

  static void openAccount() => openTab(3);

  static void clearRequest() {
    _requestedTab.value = null;
  }
}
