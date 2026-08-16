import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as plain_http;
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:realestate/features/rentals/presentation/rental_details_page.dart';
import 'app_notification_center.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'notification_preferences_service.dart';
import '../../features/lost_id/data/id_scanner_service.dart';
import '../../features/lost_id/presentation/temporary_chat_page.dart';
import '../../features/listings/models/call_invite_model.dart';
import '../../features/listings/presentation/widgets/incoming_call_dialog.dart';
import '../../features/listings/presentation/dwelly_livekit_call_page.dart';

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
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

  final body =
      message.data['body'] as String? ?? message.notification?.body ?? '';

  final isCall = type == 'CALL_INVITE' ||
      (message.data['messageType'] ?? '').toString().toUpperCase() == 'CALL_INVITE' ||
      body.contains('Call');
  final isMessage = type == 'MESSAGE' && !isCall;

  var title =
      message.data['senderName'] as String? ??
      message.data['title'] as String? ??
      message.notification?.title ??
      'Notification';
  if (title.startsWith('New message from ')) {
    title = title.replaceFirst('New message from ', '').trim();
  }

  if (isCall && Platform.isAndroid) {
    try {
      final contentStr = message.data['content'] ?? message.data['body'] ?? '';
      Map<String, dynamic>? inviteData;
      if (contentStr is String && contentStr.startsWith('{')) {
        inviteData = jsonDecode(contentStr) as Map<String, dynamic>;
      } else if (message.data['roomName'] != null) {
        inviteData = Map<String, dynamic>.from(message.data);
      }
      final roomName = inviteData?['roomName']?.toString() ?? '';
      final callerName = inviteData?['callerName']?.toString() ?? title;
      final isVideo = inviteData?['isVideo'] == true || inviteData?['isVideo']?.toString() == 'true';
      final callerAvatar = inviteData?['callerAvatar']?.toString() ?? '';

      final nativeResult = await const MethodChannel(
        'com.ishinadwelly.app/native_notification',
      ).invokeMethod('showNativeCallNotification', {
        'roomName': roomName,
        'callerName': callerName,
        'isVideo': isVideo,
        'callerAvatar': callerAvatar,
      });
      if (nativeResult == true) return;
    } catch (e) {
      print('showNativeCallNotification exception: $e');
    }
  } else if (isMessage && Platform.isAndroid) {
    final refId = message.data['referenceId'];
    try {
      print(
        'Attempting native Android inline reply notification across background engine...',
      );
      final nativeResult =
          await const MethodChannel(
            'com.ishinadwelly.app/native_notification',
          ).invokeMethod('showNativeChatNotification', {
            'chatId': refId?.toString() ?? '',
            'receiverId': message.data['senderId']?.toString() ?? '',
            'messageId': message.data['messageId']?.toString() ?? '',
            'senderName': title,
            'messageText': body,
          });
      print('showNativeChatNotification result: $nativeResult');
      if (nativeResult == true) return;
    } catch (e) {
      print('showNativeChatNotification exception: $e');
    }
  }

  // IMPORTANT: When app is in background and FCM has a 'notification' field,
  // Android system automatically shows the notification. We should NOT show
  // another local notification to avoid duplicates.
  final notification = message.notification;
  if (notification == null || isCall) {
    final channelId = isCall
        ? 'incoming_calls_v1'
        : (isMessage ? 'messages' : 'rental_alerts');
    final channelName = isCall
        ? 'Incoming Calls'
        : (isMessage ? 'Messages' : 'Rental Alerts');

    List<AndroidNotificationAction> actions = [];
    if (isCall) {
      actions = [
        const AndroidNotificationAction(
          'accept_call',
          'ACCEPT',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'decline_call',
          'DECLINE',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];
    } else if (isMessage) {
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
      '@drawable/ic_notification',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse:
          NotificationService._onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      color: const Color(0xFF0F172A),
      actions: actions,
    );

    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (isMessage) {
      final refId = message.data['referenceId'];
      if (refId != null) {
        notificationId = int.tryParse(refId.toString()) ?? notificationId;
      }
    }

    await plugin.show(
      notificationId,
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
  DartPluginRegistrant.ensureInitialized();
  print('=== BACKGROUND NOTIFICATION RESPONSE ===');
  print('Action ID: ${response.actionId}');
  print('Input: ${response.input}');
  await _handleNotificationAction(response);
}

/// Handle notification action (reply / mark as read) from any context
Future<void> _handleNotificationAction(NotificationResponse response) async {
  print('=== NOTIFICATION ACTION RECEIVED ===');
  print('Action ID: ${response.actionId}');
  print('Input: ${response.input}');
  print('Payload: ${response.payload}');

  // Always initialize plugin early so cancellation/updates in background isolate succeed
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse:
          NotificationService._onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );
  } catch (e) {
    print('Failed to initialize local notifications in isolate: $e');
  }

  final payload = response.payload;
  if (payload == null) {
    print('No payload, aborting');
    if (response.id != null) await plugin.cancel(response.id!);
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
    if (response.id != null) await plugin.cancel(response.id!);
    return;
  }

  // Read token directly from SharedPreferences (works in background isolates)
  final prefs = await SharedPreferences.getInstance();
  var token = await _resolveBackgroundAuthToken(prefs, data);
  if (token == null) {
    print('No auth token available for notification action');
    if (response.id != null) await plugin.cancel(response.id!);
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
      if (response.id != null) await plugin.cancel(response.id!);
      return;
    }

    final clientMessageId = 'notif_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final queuedUrl = '$baseUrl/conversations/$conversationId/messages/queue';
      print('Sending queued reply to: $queuedUrl');

      Future<plain_http.Response> sendQueued(String bearerToken) {
        return plain_http
            .post(
              Uri.parse(queuedUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $bearerToken',
              },
              body: jsonEncode({
                'content': replyText.trim(),
                'messageType': 'TEXT',
                'clientMessageId': clientMessageId,
              }),
            )
            .timeout(const Duration(seconds: 12));
      }

      var res = await sendQueued(token);

      if (res.statusCode == 401 || res.statusCode == 403) {
        final refreshedToken = await _resolveBackgroundAuthTokenInternal(
          prefs,
          data,
          forceRefresh: true,
        );
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          token = refreshedToken;
          print('Retrying notification reply after token refresh');
          res = await sendQueued(token);
        }
      }

      // If queue endpoint returned any error (or is unavailable), fallback to synchronous send.
      if (res.statusCode != 200 && res.statusCode != 201) {
        final syncUrl = '$baseUrl/conversations/$conversationId/messages';
        print(
          'Queue endpoint returned ${res.statusCode}; fallback to sync send: $syncUrl',
        );
        res = await plain_http
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
        final targetId = response.id ?? int.tryParse(conversationId) ?? 0;
        await plugin.show(
          targetId,
          'Sent',
          'You: ${replyText.trim()}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'messages',
              'Messages',
              importance: Importance.low,
              priority: Priority.low,
              timeoutAfter: 3500,
            ),
          ),
        );
      } else {
        print(
          'Failed to send reply: ${res.statusCode} - ${_compactResponseBody(res.body)}',
        );
        final targetId = response.id ?? int.tryParse(conversationId) ?? 0;
        await plugin.show(
          targetId,
          'Message not sent',
          'Could not deliver your reply (${res.statusCode}). Tap to open chat.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'messages',
              'Messages',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: response.payload,
        );
      }
    } catch (e) {
      print('Error sending reply: $e');
      await _enqueueNotificationReply(
        conversationId: int.tryParse(conversationId),
        content: replyText.trim(),
        clientMessageId: clientMessageId,
      );
      final targetId = response.id ?? int.tryParse(conversationId) ?? 0;
      await plugin.show(
        targetId,
        'Message queued offline',
        'Will retry when internet returns. Tap to open chat.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: response.payload,
      );
    }
  } else if (response.actionId == 'mark_read') {
    // Handle mark as read action
    try {
      final res = await plain_http
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
        if (response.id != null) {
          await plugin.cancel(response.id!);
        }
      } else {
        print('Failed to mark as read: ${res.statusCode}');
        if (response.id != null) {
          await plugin.cancel(response.id!);
        }
      }
    } catch (e) {
      print('Error marking as read: $e');
      if (response.id != null) {
        await plugin.cancel(response.id!);
      }
    }
  } else if (response.actionId == 'decline_call') {
    print('Call declined from notification action');
    if (response.id != null) {
      await plugin.cancel(response.id!);
    }
  }
}

class NotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
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
      '@drawable/ic_notification',
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

    const MethodChannel('com.ishinadwelly.app/native_notification')
        .setMethodCallHandler((call) async {
      if (call.method == 'onCallAccepted') {
        final data = Map<String, dynamic>.from(call.arguments);
        final roomName = data['roomName']?.toString() ?? '';
        final callerName = data['callerName']?.toString() ?? '';
        final isVideo = data['isVideo'] == true || data['isVideo']?.toString() == 'true';
        final callerAvatar = data['callerAvatar']?.toString() ?? '';

        final context = navigatorKey.currentState?.context;
        if (context != null && roomName.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DwellyLivekitCallPage(
                roomName: roomName,
                otherUserName: callerName,
                otherUserAvatar: callerAvatar,
                isVideo: isVideo,
              ),
            ),
          );
        }
      }
    });

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
    if (type == 'MFA_PUSH_CHALLENGE') {
      handleNotification(Map<String, dynamic>.from(message.data));
      return;
    }
    final prefs = await NotificationPreferencesService.getCachedOrDefault();
    if (!_isAllowedByPreferences(prefs, type)) {
      print('Skipping foreground notification due to preferences. type=$type');
      return;
    }
    final isMessage = type == 'MESSAGE';
    final channelId = isMessage ? 'messages' : 'rental_alerts';
    final channelName = isMessage ? 'Messages' : 'Rental Alerts';

    // Get title/body from notification field or data field (for data-only messages)
    var title =
        message.data['senderName'] as String? ??
        notification?.title ??
        message.data['title'] as String? ??
        'New Notification';
    if (title.startsWith('New message from ')) {
      title = title.replaceFirst('New message from ', '').trim();
    }
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

    final isCallAction = response.actionId == 'accept_call';
    final isNotificationAction =
        ((response.actionId != null && response.actionId!.isNotEmpty) ||
        response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction) &&
        !isCallAction;

    // If it's a background action (reply, mark_read, decline_call), handle it and do not navigate.
    if (isNotificationAction) {
      print('Calling _handleNotificationAction...');
      unawaited(_handleNotificationAction(response));
      return;
    }

    // Otherwise it's a regular tap or ACCEPT call - navigate to chat/call
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

    final isCall = body.contains('Call') ||
        (payload != null && payload.contains('CALL_INVITE'));

    // Build actions for message or call notifications
    List<AndroidNotificationAction> actions = [];
    if (isCall) {
      actions = [
        const AndroidNotificationAction(
          'accept_call',
          'ACCEPT',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'decline_call',
          'DECLINE',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];
    } else if (isMessage) {
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
      isCall ? 'incoming_calls_v1' : channelId,
      isCall ? 'Incoming Calls' : channelName,
      importance: isCall ? Importance.max : Importance.high,
      priority: isCall ? Priority.max : Priority.high,
      fullScreenIntent: isCall,
      category: isCall ? AndroidNotificationCategory.call : null,
      icon: '@drawable/ic_notification',
      color: const Color(0xFF0F172A),
      sound: isCall
          ? const RawResourceAndroidNotificationSound('incoming_call_ringtone')
          : null,
      playSound: true,
      actions: actions,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel: isCall
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      // Use conversationId (referenceId) as notification ID for messages
      // so we can cancel by conversationId later when user opens that chat
      int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (isMessage && payload != null) {
        try {
          final payloadData = jsonDecode(payload) as Map<String, dynamic>;
          final refId = payloadData['referenceId'];
          if (refId != null) {
            notificationId = int.tryParse(refId.toString()) ?? notificationId;
          }
          if (Platform.isAndroid) {
            try {
              final nativeResult =
                  await const MethodChannel(
                    'com.ishinadwelly.app/native_notification',
                  ).invokeMethod('showNativeChatNotification', {
                    'chatId': refId?.toString() ?? '',
                    'receiverId': payloadData['senderId']?.toString() ?? '',
                    'messageId': payloadData['messageId']?.toString() ?? '',
                    'senderName': title,
                    'messageText': body,
                  });
              if (nativeResult == true) return;
            } catch (_) {}
          }
        } catch (_) {}
      }
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
    final deviceName = await _getHumanReadableDeviceName();

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
          'deviceName': deviceName,
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

  static Future<String> _getHumanReadableDeviceName() async {
    try {
      if (Platform.isAndroid) {
        try {
          final modelRes = await Process.run('getprop', ['ro.product.model']);
          final brandRes = await Process.run('getprop', ['ro.product.brand']);
          final model = modelRes.stdout.toString().trim();
          final brand = brandRes.stdout.toString().trim();
          if (model.isNotEmpty) {
            if (brand.isNotEmpty &&
                !model.toLowerCase().startsWith(brand.toLowerCase())) {
              return '${_capitalize(brand)} $model';
            }
            return _capitalize(model);
          }
        } catch (_) {}
      }
    } catch (_) {}

    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host != 'localhost') {
      return host;
    }
    return Platform.isAndroid
        ? 'Android Smartphone'
        : (Platform.isIOS ? 'iPhone' : 'Mobile Device');
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Unregister device token
  static Future<bool> unregisterDevice({String? token}) async {
    if (_fcmToken == null) return true;

    try {
      final response = await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/notifications/device'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null)
                'Authorization': 'Bearer $token'
              else if (AuthService.token != null)
                'Authorization': 'Bearer ${AuthService.token}',
            },
            body: jsonEncode({'fcmToken': _fcmToken}),
          )
          .timeout(const Duration(seconds: 3));

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
    final link = (data['link'] ?? data['url']) as String?;

    if (link != null && link.isNotEmpty) {
      print('Processing link: $link');
      // Check if this link points directly to a rental listing inside Dwelly
      final rentalMatch = RegExp(r'/rental[s]?/(\d+)').firstMatch(link);
      if (rentalMatch != null) {
        final extractedId = rentalMatch.group(1);
        if (extractedId != null && extractedId.isNotEmpty) {
          print(
            'Extracted rental ID from direct URL: $extractedId. Navigating inside app...',
          );
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => RentalDetailsPage(id: extractedId),
            ),
          );
          return;
        }
      }

      // If referenceId is present for RENTAL/RENTAL_ALERT along with link, navigate directly
      if ((type == 'RENTAL_ALERT' || type == 'RENTAL' || type == 'LISTING') &&
          referenceId != null &&
          referenceId.isNotEmpty) {
        print('Navigating to rental by referenceId: $referenceId');
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => RentalDetailsPage(id: referenceId)),
        );
        return;
      }

      print('Launch external link: $link');
      try {
        final uri = Uri.parse(link);
        launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        print('Failed to launch URL: $link, error: $e');
      }
      return;
    }

    switch (type) {
      case 'RENTAL_ALERT':
      case 'RENTAL':
      case 'LISTING':
        if (referenceId != null) {
          print('Navigate to rental: $referenceId');
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => RentalDetailsPage(id: referenceId),
            ),
          );
        }
        break;
      case 'MESSAGE':
        if (referenceId != null) {
          print('Navigate to conversation: $referenceId');
        }
        break;
      case 'LOST_ID_FOUND':
      case 'LOST_ID_MATCHED':
        if (referenceId != null) {
          final foundIdId = int.tryParse(referenceId);
          if (foundIdId != null) {
            print('Launch TemporaryChat for foundId: $foundIdId');
            _launchTemporaryChatByFoundId(foundIdId);
          }
        }
        break;
      case 'MFA_PUSH_CHALLENGE':
        final challengeId = data['challengeId'] as String?;
        final challengeToken = data['challengeToken'] as String?;
        if (challengeId != null && challengeToken != null) {
          _showPushApprovalDialog(challengeId, challengeToken);
        }
        break;
      case 'CALL_INVITE':
        _showIncomingCallModalFromData(data);
        break;
      case 'CALL_CANCEL':
      case 'CALL_REJECT':
        _dismissIncomingCallModalFromData(data);
        break;
      default:
        if (referenceId != null) {
          print(
            'Navigate to rental by default if referenceId present: $referenceId',
          );
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => RentalDetailsPage(id: referenceId),
            ),
          );
        } else {
          print('Unknown notification type: $type');
        }
    }
  }

  static void _dismissIncomingCallModalFromData(Map<String, dynamic> data) {
    try {
      final context = navigatorKey.currentState?.context;
      if (context != null) {
        final roomName = data['roomName']?.toString();
        IncomingCallDialog.dismissIfOpen(context, roomName: roomName);
      }
    } catch (e) {
      print('Error dismissing incoming call modal: $e');
    }
  }

  static Future<void> _launchTemporaryChatByFoundId(int foundIdId) async {
    try {
      final chatData = await IdScannerServiceChat.startTemporaryChat(foundIdId);
      final roomId = chatData['roomId']?.toString() ?? '';
      if (roomId.isEmpty) return;
      final myRole = chatData['myRole']?.toString() ?? 'OWNER';
      final myAlias = myRole.toUpperCase() == 'FINDER'
          ? (chatData['finderAlias']?.toString() ?? 'Finder')
          : (chatData['ownerAlias']?.toString() ?? 'Owner');
      final otherAlias = myRole.toUpperCase() == 'FINDER'
          ? (chatData['ownerAlias']?.toString() ?? 'Owner')
          : (chatData['finderAlias']?.toString() ?? 'Finder');

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => TemporaryChatPage(
            roomId: roomId,
            myRole: myRole,
            myAlias: myAlias,
            otherAlias: otherAlias,
          ),
        ),
      );
    } catch (e) {
      print('Failed to open temporary chat from notification: $e');
    }
  }

  static void _showIncomingCallModalFromData(Map<String, dynamic> data) {
    try {
      final contentStr = data['content'] ?? data['body'] ?? '';
      Map<String, dynamic>? inviteData;
      if (contentStr is String && contentStr.startsWith('{')) {
        inviteData = jsonDecode(contentStr) as Map<String, dynamic>;
      } else if (data['roomName'] != null) {
        inviteData = data;
      }
      if (inviteData != null) {
        final invite = CallInviteModel.fromJson(inviteData);
        final context = navigatorKey.currentState?.context;
        if (context != null) {
          IncomingCallDialog.show(context, invite);
        }
      }
    } catch (e) {
      print('Error showing incoming call modal: $e');
    }
  }

  static Future<void> _showPushApprovalDialog(
    String challengeId,
    String challengeToken,
  ) async {
    final context = navigatorKey.currentState?.context;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Text('Sign-In Approval Request'),
          ],
        ),
        content: const Text(
          'Someone is attempting to sign in to your account. Did you initiate this sign-in request?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _respondToPushChallenge(challengeId, challengeToken, false);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deny'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _respondToPushChallenge(challengeId, challengeToken, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  static Future<void> _respondToPushChallenge(
    String challengeId,
    String challengeToken,
    bool approve,
  ) async {
    final endpoint = approve ? '/mfa/push/approve' : '/mfa/push/deny';
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengeId': challengeId,
          'challengeToken': challengeToken,
        }),
      );
      final ctx = navigatorKey.currentState?.context;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              approve ? 'Sign-in approved!' : 'Sign-in request denied.',
            ),
          ),
        );
      }
    } catch (e) {
      print('Push response error: $e');
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

  /// Clear message notifications for a specific conversation, or all if no ID given
  static Future<void> clearMessageNotifications({int? conversationId}) async {
    if (conversationId != null) {
      // Cancel notifications matching this conversation ID
      // We use the conversation ID as the notification tag
      await _localNotifications.cancel(conversationId);
      print('Cleared notification for conversation $conversationId');
    } else {
      await _localNotifications.cancelAll();
      print('Cleared all message notifications');
    }
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

Future<String?> _resolveBackgroundAuthToken(
  SharedPreferences prefs,
  Map<String, dynamic> payload,
) async {
  return _resolveBackgroundAuthTokenInternal(prefs, payload);
}

Future<String?> _resolveBackgroundAuthTokenInternal(
  SharedPreferences prefs,
  Map<String, dynamic> payload, {
  bool forceRefresh = false,
}) async {
  final cachedToken = prefs.getString('auth_token') ?? AuthService.token;
  if (!forceRefresh && cachedToken != null && cachedToken.isNotEmpty) {
    return cachedToken;
  }

  final refreshToken = prefs.getString('auth_refresh_token');
  if (refreshToken == null || refreshToken.isEmpty) {
    return null;
  }

  final payloadBaseUrl = payload['apiBaseUrl']?.toString();
  final baseUrl = _normalizeApiBaseUrl(payloadBaseUrl) ?? ApiService.baseUrl;

  try {
    final response = await plain_http
        .post(
          Uri.parse('$baseUrl/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      print('Background token refresh failed: ${response.statusCode}');
      return null;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final nextToken = decoded['token']?.toString();
    final nextRefreshToken = decoded['refreshToken']?.toString();
    if (nextToken == null || nextToken.isEmpty) {
      return null;
    }

    await prefs.setString('auth_token', nextToken);
    if (nextRefreshToken != null && nextRefreshToken.isNotEmpty) {
      await prefs.setString('auth_refresh_token', nextRefreshToken);
    }
    return nextToken;
  } catch (e) {
    print('Background token refresh error: $e');
    return null;
  }
}

Future<void> _enqueueNotificationReply({
  required int? conversationId,
  required String content,
  required String clientMessageId,
}) async {
  if (conversationId == null || conversationId <= 0 || content.isEmpty) {
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    const queueKey = 'offline_message_queue';
    final queueStr = prefs.getString(queueKey);
    final List<dynamic> queue = queueStr == null || queueStr.isEmpty
        ? <dynamic>[]
        : (jsonDecode(queueStr) as List<dynamic>);

    final alreadyQueued = queue.any((item) {
      if (item is! Map) return false;
      return item['clientMessageId']?.toString() == clientMessageId;
    });
    if (alreadyQueued) return;

    queue.add({
      'conversationId': conversationId,
      'content': content,
      'messageType': 'TEXT',
      'clientMessageId': clientMessageId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(queueKey, jsonEncode(queue));
    print('Queued notification reply locally for retry: $clientMessageId');
  } catch (e) {
    print('Failed to queue notification reply locally: $e');
  }
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
