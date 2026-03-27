import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class NotificationPreferences {
  final bool pushEnabled;
  final bool rentalAlertsEnabled;
  final bool messageEnabled;
  final bool reportUpdatesEnabled;
  final bool emailEnabled;
  final bool marketingEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final String timezone;

  const NotificationPreferences({
    this.pushEnabled = true,
    this.rentalAlertsEnabled = true,
    this.messageEnabled = true,
    this.reportUpdatesEnabled = true,
    this.emailEnabled = true,
    this.marketingEnabled = true,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.timezone = 'Africa/Nairobi',
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final rawTimezone = json['timezone']?.toString().trim();
    return NotificationPreferences(
      pushEnabled: json['pushEnabled'] ?? true,
      rentalAlertsEnabled: json['rentalAlertsEnabled'] ?? true,
      messageEnabled: json['messageEnabled'] ?? true,
      reportUpdatesEnabled: json['reportUpdatesEnabled'] ?? true,
      emailEnabled: json['emailEnabled'] ?? true,
      marketingEnabled: json['marketingEnabled'] ?? true,
      quietHoursStart: _normalizedTime(json['quietHoursStart']),
      quietHoursEnd: _normalizedTime(json['quietHoursEnd']),
      timezone: (rawTimezone != null && rawTimezone.isNotEmpty)
          ? rawTimezone
          : 'Africa/Nairobi',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushEnabled': pushEnabled,
      'rentalAlertsEnabled': rentalAlertsEnabled,
      'messageEnabled': messageEnabled,
      'reportUpdatesEnabled': reportUpdatesEnabled,
      'emailEnabled': emailEnabled,
      'marketingEnabled': marketingEnabled,
      'quietHoursStart': _normalizedTime(quietHoursStart),
      'quietHoursEnd': _normalizedTime(quietHoursEnd),
      'timezone': timezone,
    };
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? rentalAlertsEnabled,
    bool? messageEnabled,
    bool? reportUpdatesEnabled,
    bool? emailEnabled,
    bool? marketingEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    String? timezone,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      rentalAlertsEnabled: rentalAlertsEnabled ?? this.rentalAlertsEnabled,
      messageEnabled: messageEnabled ?? this.messageEnabled,
      reportUpdatesEnabled: reportUpdatesEnabled ?? this.reportUpdatesEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      marketingEnabled: marketingEnabled ?? this.marketingEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      timezone: timezone ?? this.timezone,
    );
  }

  bool allowsType(String? type) {
    if (!pushEnabled) {
      return false;
    }
    switch (type) {
      case 'MESSAGE':
        return messageEnabled;
      case 'RENTAL_ALERT':
        return rentalAlertsEnabled;
      case 'REPORT_UPDATE':
        return reportUpdatesEnabled;
      case 'MARKETING':
        return marketingEnabled;
      default:
        return true;
    }
  }

  static String? _normalizedTime(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class NotificationPreferencesService {
  static const String _prefsCacheKey = 'notification_preferences_cache_v1';
  static const String _tokenKey = 'auth_token';

  static Future<NotificationPreferences> getCachedOrDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsCacheKey);
    if (raw == null || raw.isEmpty) {
      return const NotificationPreferences();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return NotificationPreferences.fromJson(decoded);
      }
      if (decoded is Map) {
        return NotificationPreferences.fromJson(
          decoded.cast<String, dynamic>(),
        );
      }
    } catch (_) {}
    return const NotificationPreferences();
  }

  static Future<void> cache(NotificationPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCacheKey, jsonEncode(preferences.toJson()));
  }

  static Future<String?> _resolveToken(String? token) async {
    if (token != null && token.isNotEmpty) {
      return token;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<NotificationPreferences> syncFromServer({String? token}) async {
    final resolvedToken = await _resolveToken(token);
    if (resolvedToken == null || resolvedToken.isEmpty) {
      return getCachedOrDefault();
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/notifications/preferences'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $resolvedToken',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final preferences = NotificationPreferences.fromJson(decoded);
          await cache(preferences);
          return preferences;
        }
      }
    } catch (_) {}

    return getCachedOrDefault();
  }

  static Future<NotificationPreferences> updateServer(
    NotificationPreferences preferences, {
    String? token,
  }) async {
    final resolvedToken = await _resolveToken(token);
    if (resolvedToken == null || resolvedToken.isEmpty) {
      await cache(preferences);
      return preferences;
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/notifications/preferences'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $resolvedToken',
        },
        body: jsonEncode(preferences.toJson()),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final updated = NotificationPreferences.fromJson(decoded);
          await cache(updated);
          return updated;
        }
      }
    } catch (_) {}

    await cache(preferences);
    return preferences;
  }
}
