import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_notification_center.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'notification_preferences_service.dart';

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');

  final type = message.data['type'] as String?;
  final prefs = await NotificationPreferencesService.getCachedOrDefault();
  if (!_isAllowedByPreferences(prefs, type)) {
    print('Skipping background notification due to preferences. type=$type');
    return;
  }

  await AppNotificationCenter.ingestPayload(
    message.data,
    notificationId: message.messageId,
    title: message.notification?.title,
    body: message.notification?.body,
  );

  // IMPORTANT: When app is in background and FCM has a 'notification' field,
  // Android system automatically shows the notification. We should NOT show
  // another local notification to avoid duplicates.
  // Only show local notification if this is a data-only message (no notification field)
  final notification = message.notification;
  if (notification == null) {
    // Data-only message - show notification manually
    final isMessage = type == 'MESSAGE';
    final channelId = isMessage ? 'messages' : 'rental_alerts';
    final channelName = isMessage ? 'Messages' : 'Rental Alerts';
    final title = message.data['title'] as String? ?? 'Notification';
    final body = message.data['body'] as String? ?? '';

    List<AndroidNotificationAction> actions = [];
    if (isMessage) {
      actions = [
        const AndroidNotificationAction(
          'reply',
          'Reply',
          allowGeneratedReplies: true,
          showsUserInterface: false,
          inputs: [AndroidNotificationActionInput(label: 'Type a reply...')],
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark as Read',
          showsUserInterface: false,
        ),
      ];
    }

    final payloadData = Map<String, dynamic>.from(message.data);
    payloadData['apiBaseUrl'] = ApiService.baseUrl;

    final plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onBackgroundNotificationResponse,
    );

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      actions: actions,
    );

    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode(payloadData),
    );
  }
  // If notification field exists, Android already showed it - skip to avoid duplicate
}

// Top-level function for handling notification actions in background
@pragma('vm:entry-point')
Future<void> _onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  print('=== BACKGROUND NOTIFICATION RESPONSE ===');
  print('Action ID: ${response.actionId}');
  print('Input: ${response.input}');
  // This runs in a separate isolate, so we need to handle it carefully
  await _handleNotificationAction(response);
}

/// Handle notification action (reply / mark as read) from any context
Future<void> _handleNotificationAction(NotificationResponse response) async {
  print('=== NOTIFICATION ACTION RECEIVED ===');
  print('Action ID: ${response.actionId}');
  print('Input: ${response.input}');
  print('Payload: ${response.payload}');

  final payload = response.payload;
  if (payload == null) {
    print('No payload, aborting');
    return;
  }

  final data = jsonDecode(payload) as Map<String, dynamic>;
  print('Decoded data: $data');

  // referenceId could be String or int depending on JSON parsing
  final referenceIdRaw = data['referenceId'];
  final conversationId = referenceIdRaw?.toString();
  final type = data['type'] as String?;

  print('Conversation ID: $conversationId, Type: $type');

  if (type != 'MESSAGE' || conversationId == null) {
    print('Not a MESSAGE or no conversationId, aborting');
    return;
  }

  // Read token directly from SharedPreferences (works in background isolates)
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  if (token == null) {
    print('No auth token available for notification action');
    return;
  }

  final payloadBaseUrl = data['apiBaseUrl']?.toString();
  final baseUrl = _normalizeApiBaseUrl(payloadBaseUrl) ?? ApiService.baseUrl;
  print('Base URL: $baseUrl');

  if (response.actionId == 'reply') {
    // Handle reply action
    final replyText = response.input;
    print('Reply text: $replyText');
    if (replyText == null || replyText.trim().isEmpty) {
      print('Empty reply, aborting');
      return;
    }

    try {
      final clientMessageId = 'notif_${DateTime.now().microsecondsSinceEpoch}';
      final queuedUrl = '$baseUrl/conversations/$conversationId/messages/queue';
      print('Sending queued reply to: $queuedUrl');

      var res = await http
          .post(
            Uri.parse(queuedUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'content': replyText.trim(),
              'messageType': 'TEXT',
              'clientMessageId': clientMessageId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      // Backward/alternative fallback if queue path is unavailable.
      if (res.statusCode == 404 || res.statusCode == 405) {
        final syncUrl = '$baseUrl/conversations/$conversationId/messages';
        print('Queue endpoint unavailable; fallback to sync send: $syncUrl');
        res = await http
            .post(
              Uri.parse(syncUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'content': replyText.trim(),
                'messageType': 'TEXT',
              }),
            )
            .timeout(const Duration(seconds: 12));
      }

      print(
        'Reply response: ${res.statusCode} - ${_compactResponseBody(res.body)}',
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        print('Reply sent successfully to conversation $conversationId');
        // Cancel the original notification instead of showing confirmation
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.cancelAll();
      } else {
        print(
          'Failed to send reply: ${res.statusCode} - ${_compactResponseBody(res.body)}',
        );
      }
    } catch (e) {
      print('Error sending reply: $e');
    }
  } else if (response.actionId == 'mark_read') {
    // Handle mark as read action
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/conversations/$conversationId/read'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        print('Marked conversation $conversationId as read');
      } else {
        print('Failed to mark as read: ${res.statusCode}');
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }
}

class NotificationService {
  static String? _fcmToken;
  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static String? get fcmToken => _fcmToken;
  static bool get isInitialized => _initialized;

  /// Initialize FCM and local notifications
  static Future<void> init() async {
    if (_initialized) return;

    try {
      await AppNotificationCenter.init();

      // Initialize Firebase (should already be done in main.dart)
      await Firebase.initializeApp();

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('User granted provisional permission');
      } else {
        print('User declined or has not accepted permission');
      }

      // Initialize local notifications
      await _initLocalNotifications();

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      print('FCM Token: $_fcmToken');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        if (AuthService.isLoggedIn) {
          registerDevice(token);
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle message taps (app was in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      _initialized = true;

      // Register device if logged in
      if (AuthService.isLoggedIn && _fcmToken != null) {
        await registerDevice(_fcmToken!);
      }

      await NotificationPreferencesService.syncFromServer(
        token: AuthService.token,
      );
    } catch (e) {
      print('Failed to initialize notifications: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // Create notification channels for Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    const rentalChannel = AndroidNotificationChannel(
      'rental_alerts',
      'Rental Alerts',
      description: 'Notifications for new rental listings',
      importance: Importance.high,
    );
    await androidPlugin?.createNotificationChannel(rentalChannel);

    const messagesChannel = AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'Chat message notifications',
      importance: Importance.high,
    );
    await androidPlugin?.createNotificationChannel(messagesChannel);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    _handleForegroundMessageAsync(message);
  }

  static Future<void> _handleForegroundMessageAsync(
    RemoteMessage message,
  ) async {
    print('=== FCM FOREGROUND MESSAGE RECEIVED ===');
    print('Message ID: ${message.messageId}');
    print('Message data: ${message.data}');
    print('Has notification: ${message.notification != null}');
    if (message.notification != null) {
      print('Notification title: ${message.notification!.title}');
      print('Notification body: ${message.notification!.body}');
    }

    final notification = message.notification;
    final type = message.data['type'] as String?;
    final prefs = await NotificationPreferencesService.getCachedOrDefault();
    if (!_isAllowedByPreferences(prefs, type)) {
      print('Skipping foreground notification due to preferences. type=$type');
      return;
    }
    final isMessage = type == 'MESSAGE';
    final channelId = isMessage ? 'messages' : 'rental_alerts';
    final channelName = isMessage ? 'Messages' : 'Rental Alerts';

    // Get title/body from notification field or data field (for data-only messages)
    final title =
        notification?.title ??
        message.data['title'] as String? ??
        'New Notification';
    final body = notification?.body ?? message.data['body'] as String? ?? '';

    await AppNotificationCenter.ingestPayload(
      message.data,
      notificationId: message.messageId,
      title: title,
      body: body,
    );

    print(
      'Showing local notification - title: $title, body: $body, channel: $channelId',
    );

    final payloadData = Map<String, dynamic>.from(message.data);
    payloadData['apiBaseUrl'] = ApiService.baseUrl;

    _showLocalNotification(
      title: title,
      body: body,
      payload: jsonEncode(payloadData),
      channelId: channelId,
      channelName: channelName,
      isMessage: isMessage,
    );

    print('=== LOCAL NOTIFICATION SHOWN ===');
  }

  static void _handleMessageTap(RemoteMessage message) {
    print('Message tapped: ${message.messageId}');
    handleNotification(message.data);
  }

  static void _onNotificationResponse(NotificationResponse response) {
    print('=== _onNotificationResponse CALLED ===');
    print('Action ID: ${response.actionId}');
    print('Input: ${response.input}');
    print('Payload: ${response.payload}');
    print('Notification Response Type: ${response.notificationResponseType}');

    final isNotificationAction =
        (response.actionId != null && response.actionId!.isNotEmpty) ||
        response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction;

    // If it's an action (reply or mark_read), handle it and never navigate.
    if (isNotificationAction) {
      print('Calling _handleNotificationAction...');
      unawaited(_handleNotificationAction(response));
      return;
    }

    // Otherwise it's a regular tap - navigate
    if (response.payload != null) {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      handleNotification(data);
    }
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = 'rental_alerts',
    String channelName = 'Rental Alerts',
    bool isMessage = false,
  }) async {
    print(
      '_showLocalNotification called: title=$title, body=$body, channel=$channelId',
    );

    // Build actions for message notifications
    List<AndroidNotificationAction> actions = [];
    if (isMessage) {
      actions = [
        const AndroidNotificationAction(
          'reply',
          'Reply',
          allowGeneratedReplies: true,
          showsUserInterface: false,
          inputs: [AndroidNotificationActionInput(label: 'Type a reply...')],
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark as Read',
          showsUserInterface: false,
        ),
      ];
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      actions: actions,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('Calling _localNotifications.show with id=$notificationId');
      await _localNotifications.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );
      print('_localNotifications.show completed successfully');
    } catch (e) {
      print('ERROR showing local notification: $e');
    }
  }

  /// Register device token with backend
  static Future<bool> registerDevice(String fcmToken) async {
    if (!AuthService.isLoggedIn) {
      return false;
    }

    _fcmToken = fcmToken;

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/notifications/device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'fcmToken': fcmToken,
          'deviceType': Platform.isAndroid ? 'ANDROID' : 'IOS',
          'deviceName': Platform.localHostname,
          'appVersion': '1.0.0',
        }),
      );
      final ok = response.statusCode == 200;
      if (ok) {
        await NotificationPreferencesService.syncFromServer(
          token: AuthService.token,
        );
      }
      return ok;
    } catch (e) {
      print('Register device error: $e');
      return false;
    }
  }

  /// Unregister device token
  static Future<bool> unregisterDevice() async {
    if (_fcmToken == null) return true;

    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/notifications/device'),
        headers: {
          'Content-Type': 'application/json',
          if (AuthService.token != null)
            'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'fcmToken': _fcmToken}),
      );

      if (response.statusCode == 200) {
        _fcmToken = null;
        return true;
      }
      return false;
    } catch (e) {
      print('Unregister device error: $e');
      return false;
    }
  }

  static Future<void> syncPreferences() async {
    await NotificationPreferencesService.syncFromServer(
      token: AuthService.token,
    );
  }

  /// Handle incoming notification data
  static void handleNotification(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final referenceId = data['referenceId'] as String?;

    switch (type) {
      case 'RENTAL_ALERT':
        if (referenceId != null) {
          // Navigate to rental detail
          // You can use a GlobalKey<NavigatorState> or a navigation service
          print('Navigate to rental: $referenceId');
        }
        break;
      case 'MESSAGE':
        if (referenceId != null) {
          // Navigate to conversation
          print('Navigate to conversation: $referenceId');
        }
        break;
      default:
        print('Unknown notification type: $type');
    }
  }

  /// Send test notification (for development)
  static Future<bool> sendTestNotification({
    String title = 'Test Notification',
    String message = 'This is a test notification',
  }) async {
    if (!AuthService.isLoggedIn) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/notifications/test'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'title': title, 'message': message}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Send test notification error: $e');
      return false;
    }
  }

  /// Subscribe to a topic (e.g., for area-based notifications)
  static Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }

  /// Clear all message notifications (call when opening messaging tab)
  static Future<void> clearMessageNotifications() async {
    await _localNotifications.cancelAll();
    print('Cleared all message notifications');
  }
}

bool _isAllowedByPreferences(NotificationPreferences prefs, String? type) {
  if (!prefs.pushEnabled) {
    return false;
  }
  if (!_isQuietHoursAllowed(prefs)) {
    return false;
  }
  return prefs.allowsType(type);
}

bool _isQuietHoursAllowed(NotificationPreferences prefs) {
  final start = prefs.quietHoursStart;
  final end = prefs.quietHoursEnd;
  if (start == null || end == null) {
    return true;
  }

  final startMinutes = _toMinutes(start);
  final endMinutes = _toMinutes(end);
  if (startMinutes == null || endMinutes == null) {
    return true;
  }

  final now = DateTime.now();
  final current = now.hour * 60 + now.minute;
  if (startMinutes == endMinutes) {
    return false;
  }
  if (startMinutes < endMinutes) {
    return current < startMinutes || current >= endMinutes;
  }
  return current < startMinutes && current >= endMinutes;
}

int? _toMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

String? _normalizeApiBaseUrl(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }

  var normalized = rawValue.trim();
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }

  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  Uri? uri;
  try {
    uri = Uri.parse(normalized);
  } catch (_) {
    return null;
  }

  if (!uri.hasScheme || uri.host.isEmpty) {
    return null;
  }

  if (!normalized.endsWith('/api')) {
    normalized = '$normalized/api';
  }
  return normalized;
}

String _compactResponseBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '<empty>';
  final lower = trimmed.toLowerCase();
  if (lower.contains('<html') || lower.contains('<!doctype html')) {
    return '<html-error-body-suppressed>';
  }
  const maxLen = 200;
  if (trimmed.length <= maxLen) return trimmed;
  return '${trimmed.substring(0, maxLen)}...';
}
