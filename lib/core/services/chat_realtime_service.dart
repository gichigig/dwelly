import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../models/chat.dart';
import '../models/chat_group.dart';
import '../errors/app_error.dart';
import 'api_service.dart';
import 'auth_service.dart';

class MessageStatusEvent {
  final int conversationId;
  final String? clientMessageId;
  final String status; // QUEUED | SENT | WARNING | FAILED
  final String? reasonCode;
  final ChatMessage? message;

  const MessageStatusEvent({
    required this.conversationId,
    required this.status,
    this.clientMessageId,
    this.reasonCode,
    this.message,
  });

  factory MessageStatusEvent.fromJson(Map<String, dynamic> json) {
    return MessageStatusEvent(
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'FAILED').toString(),
      clientMessageId: json['clientMessageId'] as String?,
      reasonCode: json['reasonCode'] as String?,
      message: json['message'] != null
          ? ChatMessage.fromJson(json['message'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TypingEvent {
  final int conversationId;
  final int userId;
  final bool isTyping;

  const TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
  });

  factory TypingEvent.fromJson(Map<String, dynamic> json) {
    return TypingEvent(
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      isTyping: json['isTyping'] == true || json['typing'] == true,
    );
  }
}

class ReadReceiptEvent {
  final int conversationId;
  final int readByUserId;
  final String readAt;

  const ReadReceiptEvent({
    required this.conversationId,
    required this.readByUserId,
    required this.readAt,
  });

  factory ReadReceiptEvent.fromJson(Map<String, dynamic> json) {
    return ReadReceiptEvent(
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      readByUserId: (json['readByUserId'] as num?)?.toInt() ?? 0,
      readAt: (json['readAt'] ?? '').toString(),
    );
  }
}

class ChatRealtimeService {
  static final ChatRealtimeService _instance = ChatRealtimeService._internal();
  factory ChatRealtimeService() => _instance;
  ChatRealtimeService._internal();

  StompClient? _client;
  bool _isConnected = false;
  DateTime? _lastDisconnectedAt;

  bool get isConnected => _isConnected;
  DateTime? get lastDisconnectedAt => _lastDisconnectedAt;
  void clearDisconnectTimestamp() => _lastDisconnectedAt = null;

  Future<void> connect({
    required VoidCallback onConnected,
    required ValueChanged<AppError> onError,
  }) async {
    if (_isConnected) return;
    final token = AuthService.token;
    if (token == null || token.isEmpty) {
      return;
    }

    final wsUrl = _toWsUrl(ApiService.baseUrl);
    _client = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        heartbeatIncoming: const Duration(seconds: 8),
        heartbeatOutgoing: const Duration(seconds: 8),
        reconnectDelay: Duration(seconds: 5 + Random().nextInt(6)), // Thundering herd jitter: 5-10s
        onConnect: (frame) {
          _isConnected = true;
          onConnected();
        },
        onWebSocketError: (dynamic error) {
          _isConnected = false;
          _lastDisconnectedAt ??= DateTime.now();
          onError(
            const AppError(
              code: AppErrorCode.network,
              message:
                  'Live chat connection is unavailable. Falling back to sync.',
              retryable: true,
            ),
          );
        },
        onStompError: (frame) {
          _isConnected = false;
          _lastDisconnectedAt ??= DateTime.now();
          onError(
            const AppError(
              code: AppErrorCode.server,
              message:
                  'Live chat connection failed. Falling back to sync updates.',
              retryable: true,
            ),
          );
        },
        onDisconnect: (frame) {
          _isConnected = false;
          _lastDisconnectedAt ??= DateTime.now();
        },
        onDebugMessage: (message) {
          if (!kDebugMode) return;
          debugPrint('STOMP: $message');
        },
      ),
    );
    _client?.activate();
  }

  StompUnsubscribe? subscribeConversation(
    int conversationId,
    ValueChanged<ChatMessage> onMessage,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/conversation/$conversationId',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onMessage(ChatMessage.fromJson(decoded));
        } catch (_) {
          // Ignore malformed events.
        }
      },
    );
  }

  StompUnsubscribe? subscribeGroupMessages(
    int groupId,
    ValueChanged<GroupMessage> onMessage,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/group/$groupId',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onMessage(GroupMessage.fromJson(decoded));
        } catch (_) {
          // Ignore malformed events.
        }
      },
    );
  }

  StompUnsubscribe? subscribeGroupDetails(
    int groupId,
    ValueChanged<ChatGroup> onGroupDetails,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/group/$groupId/details',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onGroupDetails(ChatGroup.fromJson(decoded));
        } catch (_) {
          // Ignore malformed events.
        }
      },
    );
  }

  StompUnsubscribe? subscribeUserMessageStatus(
    int userId,
    ValueChanged<MessageStatusEvent> onEvent,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/user/$userId/message-status',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onEvent(MessageStatusEvent.fromJson(decoded));
        } catch (_) {
          // Ignore malformed events.
        }
      },
    );
  }

  StompUnsubscribe? subscribeUserTyping(
    int userId,
    ValueChanged<TypingEvent> onEvent,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/user/$userId/typing',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onEvent(TypingEvent.fromJson(decoded));
        } catch (_) {}
      },
    );
  }

  StompUnsubscribe? subscribeUserReadReceipts(
    int userId,
    ValueChanged<ReadReceiptEvent> onEvent,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/user/$userId/read-receipts',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onEvent(ReadReceiptEvent.fromJson(decoded));
        } catch (_) {}
      },
    );
  }

  void sendTypingEvent(int conversationId, bool isTyping) {
    if (!_isConnected || _client == null) return;
    _client!.send(
      destination: '/app/chat/$conversationId/typing',
      body: jsonEncode({'isTyping': isTyping, 'typing': isTyping}),
    );
  }

  void sendReadReceiptEvent(int conversationId) {
    if (!_isConnected || _client == null) return;
    _client!.send(
      destination: '/app/chat/$conversationId/read',
      body: jsonEncode({}),
    );
  }

  StompUnsubscribe? subscribeUserGroups(
    int userId,
    ValueChanged<ChatGroup> onGroup,
  ) {
    if (!_isConnected || _client == null) return null;
    return _client!.subscribe(
      destination: '/topic/user/$userId/groups',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          onGroup(ChatGroup.fromJson(decoded));
        } catch (_) {
          // Ignore malformed events.
        }
      },
    );
  }

  Future<void> disconnect() async {
    try {
      _client?.deactivate();
    } catch (_) {
      // ignore
    } finally {
      _client = null;
      _isConnected = false;
    }
  }

  String _toWsUrl(String baseApiUrl) {
    final parsed = Uri.parse(baseApiUrl);
    final wsScheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    final segments = List<String>.from(parsed.pathSegments);
    if (segments.isNotEmpty && segments.last == 'api') {
      segments.removeLast();
    }
    segments.add('ws');
    return Uri(
      scheme: wsScheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      pathSegments: segments,
    ).toString();
  }
}
