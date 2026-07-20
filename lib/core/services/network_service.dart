import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkStatus { online, offline, slow, backOnline }

class NetworkService {
  NetworkService._();
  static final NetworkService instance = NetworkService._();

  final ValueNotifier<NetworkStatus> status = ValueNotifier(
    NetworkStatus.online,
  );

  StreamSubscription? _connectivitySubscription;
  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _isForeground = true;

  static const Duration _foregroundPollingInterval = Duration(seconds: 45);

  void initialize() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      // The new API returns a list of ConnectivityResult
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnection) {
        _updateStatus(NetworkStatus.offline);
      } else {
        if (_isForeground) {
          checkNetwork();
        }
      }
    });

    _startPolling();

    checkNetwork();
  }

  void setAppForeground(bool isForeground) {
    if (_isForeground == isForeground) return;
    _isForeground = isForeground;
    if (_isForeground) {
      _startPolling();
      checkNetwork();
    } else {
      _stopPolling();
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _stopPolling();
    status.dispose();
  }

  void _startPolling() {
    _stopPolling();
    // Periodic check to recover if the OS fails to deliver connectivity events.
    _pollingTimer = Timer.periodic(_foregroundPollingInterval, (_) {
      if (status.value == NetworkStatus.offline ||
          status.value == NetworkStatus.slow) {
        checkNetwork();
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> checkNetwork() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final stopwatch = Stopwatch()..start();

      // Try connecting to a highly available server on standard HTTP port 80
      // TCP Port 53 to 8.8.8.8 is often blocked by mobile carrier firewalls!
      final socket = await Socket.connect(
        'example.com',
        80,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();

      stopwatch.stop();

      // If it takes more than 1.5 seconds, we consider it 'slow'
      if (stopwatch.elapsedMilliseconds > 1500) {
        _updateStatus(NetworkStatus.slow);
      } else {
        _updateStatus(NetworkStatus.online);
      }
    } catch (_) {
      // Socket exception or timeout means we are offline or DNS failed
      _updateStatus(NetworkStatus.offline);
    } finally {
      _isChecking = false;
    }
  }

  void _updateStatus(NetworkStatus newStatus) {
    if (status.value == newStatus) return;

    // If we are recovering from offline/slow, show "Back Online" briefly
    if ((status.value == NetworkStatus.offline ||
            status.value == NetworkStatus.slow) &&
        newStatus == NetworkStatus.online) {
      status.value = NetworkStatus.backOnline;
      Future.delayed(const Duration(seconds: 3), () {
        if (status.value == NetworkStatus.backOnline) {
          status.value = NetworkStatus.online;
        }
      });
    } else {
      status.value = newStatus;
    }
  }
}
