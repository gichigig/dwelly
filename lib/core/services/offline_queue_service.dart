import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:realestate/core/services/chat_service.dart';

class OfflineMessage {
  final int? conversationId;
  final int? rentalId;
  final int? targetUserId;
  final String content;
  final String messageType;
  final String? mediaUrl;
  final String clientMessageId;
  final DateTime createdAt;

  OfflineMessage({
    this.conversationId,
    this.rentalId,
    this.targetUserId,
    required this.content,
    required this.messageType,
    this.mediaUrl,
    required this.clientMessageId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'rentalId': rentalId,
    'targetUserId': targetUserId,
    'content': content,
    'messageType': messageType,
    'mediaUrl': mediaUrl,
    'clientMessageId': clientMessageId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OfflineMessage.fromJson(Map<String, dynamic> json) => OfflineMessage(
    conversationId: json['conversationId'],
    rentalId: json['rentalId'],
    targetUserId: json['targetUserId'],
    content: json['content'],
    messageType: json['messageType'] ?? 'TEXT',
    mediaUrl: json['mediaUrl'],
    clientMessageId: json['clientMessageId'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class OfflineQueueService {
  static const String _queueKey = 'offline_message_queue';
  static final _sentMessageController = StreamController<String>.broadcast();
  static Stream<String> get onMessageSent => _sentMessageController.stream;

  static bool _isProcessing = false;
  static StreamSubscription? _connectivitySubscription;

  static Future<void> init() async {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      if (result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet)) {
        _processQueue();
      }
    });
    _processQueue();
  }

  static Future<void> enqueueMessage(OfflineMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await _getQueue(prefs);

    if (!queue.any((m) => m.clientMessageId == message.clientMessageId)) {
      queue.add(message);
      await _saveQueue(prefs, queue);
    }
  }

  static Future<List<OfflineMessage>> _getQueue(SharedPreferences prefs) async {
    final queueStr = prefs.getString(_queueKey);
    if (queueStr == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(queueStr);
      return decoded.map((e) => OfflineMessage.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveQueue(
    SharedPreferences prefs,
    List<OfflineMessage> queue,
  ) async {
    final encoded = jsonEncode(queue.map((e) => e.toJson()).toList());
    await prefs.setString(_queueKey, encoded);
  }

  static Future<void> _removeFromQueue(String clientMessageId) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await _getQueue(prefs);
    queue.removeWhere((m) => m.clientMessageId == clientMessageId);
    await _saveQueue(prefs, queue);
  }

  static Future<void> _processQueue() async {
    if (_isProcessing) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.mobile) &&
        !connectivity.contains(ConnectivityResult.wifi) &&
        !connectivity.contains(ConnectivityResult.ethernet)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final queue = await _getQueue(prefs);

    if (queue.isEmpty) return;

    _isProcessing = true;

    try {
      for (final msg in List<OfflineMessage>.from(queue)) {
        try {
          if (msg.conversationId != null && msg.conversationId! > 0) {
            final result = await ChatService.sendMessageQueued(
              conversationId: msg.conversationId!,
              content: msg.content,
              messageType: msg.messageType,
              mediaUrl: msg.mediaUrl,
              clientMessageId: msg.clientMessageId,
            );

            if (result.status == 'OFFLINE_QUEUED') {
              break; // Still no network
            }

            if (result.isSent || result.isFailed) {
              await _removeFromQueue(msg.clientMessageId);
              if (result.isSent)
                _sentMessageController.add(msg.clientMessageId);
            }
          } else {
            final result =
                await ChatService.startConversationAndSendMessageQueued(
                  rentalId: msg.rentalId,
                  targetUserId: msg.targetUserId,
                  content: msg.content,
                  messageType: msg.messageType,
                  mediaUrl: msg.mediaUrl,
                  clientMessageId: msg.clientMessageId,
                );

            if (result.messageResult.status == 'OFFLINE_QUEUED') {
              break; // Still no network
            }

            if (result.messageResult.isSent || result.messageResult.isFailed) {
              await _removeFromQueue(msg.clientMessageId);
              if (result.messageResult.isSent)
                _sentMessageController.add(msg.clientMessageId);
            }
          }
        } catch (e) {
          // Unhandled errors, skip and retry later or remove depending on error type
          if (e.toString().toLowerCase().contains('network') ||
              e.toString().toLowerCase().contains('timeout')) {
            break; // network error, stop processing
          } else {
            // For unhandled non-network errors, we should probably remove it so it doesn't block the queue forever
            await _removeFromQueue(msg.clientMessageId);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  static void dispose() {
    _connectivitySubscription?.cancel();
    _sentMessageController.close();
  }
}
