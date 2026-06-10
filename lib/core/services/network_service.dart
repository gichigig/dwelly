import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkStatus { online, offline, slow, backOnline }

class NetworkService {
  NetworkService._();
  static final NetworkService instance = NetworkService._();

  final ValueNotifier<NetworkStatus> status = ValueNotifier(NetworkStatus.online);

  StreamSubscription? _connectivitySubscription;
  bool _isChecking = false;

  void initialize() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      // The new API returns a list of ConnectivityResult
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnection) {
        _updateStatus(NetworkStatus.offline);
      } else {
        checkNetwork();
      }
    });

    checkNetwork();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    status.dispose();
  }

  Future<void> checkNetwork() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final stopwatch = Stopwatch()..start();
      
      // Try resolving Google's DNS via TCP to measure latency
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
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
    if ((status.value == NetworkStatus.offline || status.value == NetworkStatus.slow) && 
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
