import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../models/chat.dart';
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
      clientMessageId: json['clientMessageId']?.toString(),
      reasonCode: json['reasonCode']?.toString(),
      message: json['message'] is Map<String, dynamic>
          ? ChatMessage.fromJson(json['message'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ChatRealtimeService {
  StompClient? _client;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

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
        reconnectDelay: const Duration(seconds: 4),
        onConnect: (frame) {
          _isConnected = true;
          onConnected();
        },
        onWebSocketError: (dynamic error) {
          _isConnected = false;
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
