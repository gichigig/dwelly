import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notifications/domain/notification_model.dart';

class AppNotificationCenter {
  static const String _storageKey = 'app_notifications_v1';
  static const int _maxStoredNotifications = 100;

  static final ValueNotifier<List<NotificationModel>> notifications =
      ValueNotifier<List<NotificationModel>>(<NotificationModel>[]);
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) {
      await reload();
      return;
    }
    _initialized = true;
    await reload();
  }

  static Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _setNotifications(const <NotificationModel>[]);
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _setNotifications(const <NotificationModel>[]);
        return;
      }
      final items =
          decoded
              .whereType<Map>()
              .map(
                (item) =>
                    NotificationModel.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _setNotifications(items);
    } catch (_) {
      _setNotifications(const <NotificationModel>[]);
    }
  }

  static Future<void> addNotification(NotificationModel notification) async {
    final prefs = await SharedPreferences.getInstance();
    final next = <NotificationModel>[
      notification,
      ...notifications.value.where((item) => item.id != notification.id),
    ];
    final trimmed = next.take(_maxStoredNotifications).toList();
    await _persist(prefs, trimmed);
    _setNotifications(trimmed);
  }

  static Future<void> ingestPayload(
    Map<String, dynamic> data, {
    String? notificationId,
    String? title,
    String? body,
  }) async {
    final resolvedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : (data['title']?.toString().trim().isNotEmpty == true
              ? data['title'].toString().trim()
              : 'Notification');
    final resolvedBody = body?.trim().isNotEmpty == true
        ? body!.trim()
        : (data['body']?.toString().trim().isNotEmpty == true
              ? data['body'].toString().trim()
              : '');
    final id = notificationId?.trim().isNotEmpty == true
        ? notificationId!.trim()
        : (data['notificationId']?.toString().trim().isNotEmpty == true
              ? data['notificationId'].toString().trim()
              : 'notif_${DateTime.now().microsecondsSinceEpoch}');

    await addNotification(
      NotificationModel(
        id: id,
        title: resolvedTitle,
        message: resolvedBody,
        createdAt: DateTime.now(),
        targetRoute: _targetRouteForType(data['type']?.toString()),
        type: data['type']?.toString(),
        referenceId: data['referenceId']?.toString(),
      ),
    );
  }

  static Future<void> markAsRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = notifications.value
        .map(
          (notification) => notification.id == id
              ? notification.copyWith(isRead: true)
              : notification,
        )
        .toList();
    await _persist(prefs, updated);
    _setNotifications(updated);
  }

  static Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final updated = notifications.value
        .map((notification) => notification.copyWith(isRead: true))
        .toList();
    await _persist(prefs, updated);
    _setNotifications(updated);
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = notifications.value
        .where((notification) => notification.id != id)
        .toList();
    await _persist(prefs, updated);
    _setNotifications(updated);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _setNotifications(const <NotificationModel>[]);
  }

  static Future<void> _persist(
    SharedPreferences prefs,
    List<NotificationModel> items,
  ) async {
    await prefs.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  static void _setNotifications(List<NotificationModel> items) {
    notifications.value = List<NotificationModel>.unmodifiable(items);
    unreadCount.value = items.where((item) => !item.isRead).length;
  }

  static String? _targetRouteForType(String? type) {
    final upper = type?.trim().toUpperCase();
    switch (upper) {
      case 'MESSAGE':
        return '/inbox';
      case 'ACCOUNT':
      case 'AUTH':
        return '/account';
      default:
        return null;
    }
  }
}
