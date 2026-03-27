import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class CrashReportingService {
  static final http.Client _client = http.Client();
  static DateTime? _lastSentAt;
  static String? _lastFingerprint;

  static Future<void> reportFlutterError(FlutterErrorDetails details) async {
    await _report(
      category: details.exception.runtimeType.toString(),
      message: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
    );
  }

  static Future<void> reportUnhandled(
    Object error,
    StackTrace? stackTrace,
  ) async {
    await _report(
      category: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  static Future<void> _report({
    required String category,
    required String message,
    String? stackTrace,
  }) async {
    final payload = <String, dynamic>{
      'platform': kIsWeb ? 'WEB_APP' : 'FLUTTER_APP',
      'category': _truncate(category, 64),
      'message': _truncate(message, 800),
      'stackTrace': _truncate(stackTrace, 24000),
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'fingerprint': _fingerprint(category, message, stackTrace),
    };

    final fingerprint = payload['fingerprint'] as String;
    final now = DateTime.now();
    if (_lastFingerprint == fingerprint &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!).inSeconds < 5) {
      return;
    }
    _lastFingerprint = fingerprint;
    _lastSentAt = now;

    final uri = Uri.parse('${ApiService.baseUrl}/telemetry/crashes');
    try {
      await _client
          .post(
            uri,
            headers: ApiService.getHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Telemetry must never block user flow.
    }
  }

  static String _fingerprint(
    String category,
    String message,
    String? stackTrace,
  ) {
    final normalized = '$category|$message|${stackTrace ?? ''}'
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return normalized.hashCode.toRadixString(16);
  }

  static String? _truncate(String? value, int max) {
    if (value == null || value.isEmpty) return null;
    return value.length <= max ? value : value.substring(0, max);
  }
}
