import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat.dart';
import '../errors/app_error.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'cache_service.dart';

class PaginatedConversations {
  final List<Conversation> conversations;
  final bool hasMore;
  final int page;
  final int size;
  final int totalConversations;

  PaginatedConversations({
    required this.conversations,
    required this.hasMore,
    required this.page,
    required this.size,
    required this.totalConversations,
  });
}

class QueuedSendResult {
  final String status; // QUEUED | SENT | FAILED
  final String? mode; // QUEUE | SYNC_FALLBACK
  final String clientMessageId;
  final String? queueMessageId;
  final String? reason;
  final ChatMessage? message;

  const QueuedSendResult({
    required this.status,
    required this.clientMessageId,
    this.mode,
    this.queueMessageId,
    this.reason,
    this.message,
  });

  bool get isQueued => status.toUpperCase() == 'QUEUED';
  bool get isSent => status.toUpperCase() == 'SENT';
  bool get isFailed => status.toUpperCase() == 'FAILED';

  factory QueuedSendResult.fromJson(Map<String, dynamic> json) {
    return QueuedSendResult(
      status: (json['status'] ?? 'FAILED').toString(),
      mode: json['mode']?.toString(),
      clientMessageId: (json['clientMessageId'] ?? '').toString(),
      queueMessageId: json['queueMessageId']?.toString(),
      reason: json['reason']?.toString(),
      message: json['message'] is Map<String, dynamic>
          ? ChatMessage.fromJson(json['message'] as Map<String, dynamic>)
          : null,
    );
  }
}

class QueuedConversationSendResult {
  final Conversation conversation;
  final QueuedSendResult messageResult;

  const QueuedConversationSendResult({
    required this.conversation,
    required this.messageResult,
  });

  factory QueuedConversationSendResult.fromJson(Map<String, dynamic> json) {
    return QueuedConversationSendResult(
      conversation: Conversation.fromJson(
        json['conversation'] as Map<String, dynamic>? ?? const {},
      ),
      messageResult: QueuedSendResult.fromJson(
        json['message'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

enum ChatSafetyFilterMode { all, muted, blocked }

class ChatService {
  static final ValueNotifier<int> safetyVisibilityVersion = ValueNotifier<int>(
    0,
  );
  static final ValueNotifier<int> unreadMessageCount = ValueNotifier<int>(0);

  static void notifySafetyVisibilityChanged() {
    safetyVisibilityVersion.value = safetyVisibilityVersion.value + 1;
  }

  static void invalidateListingVisibilityCaches() {
    ApiService.invalidateCachedGetByPath('/rentals/paginated');
    ApiService.invalidateCachedGetByPath('/rentals/search/nearby');
    ApiService.invalidateCachedGetByPath('/rentals/recommendations');
    ApiService.invalidateCachedGetByPath('/marketplace/products');
    notifySafetyVisibilityChanged();
  }

  static bool _isAuthError(int statusCode) {
    // 403 is often an authorization/domain rule (e.g. blocked contact), not
    // an expired session. Logging out on 403 causes incorrect forced sign-out.
    return statusCode == 401;
  }

  static Future<void> _handleAuthError(int statusCode) async {
    if (_isAuthError(statusCode)) {
      await AuthService.logout();
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Your session expired. Please sign in again.',
        retryable: true,
      );
    }
  }

  static Future<List<Conversation>> getConversations({
    bool forceRefresh = false,
    String? listingType,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    // Return cached conversations if available
    if (!forceRefresh && (listingType == null || listingType.isEmpty)) {
      final cached = CacheManager.conversations.value;
      if (cached != null) {
        final conversations = cached.cast<Conversation>();
        _updateUnreadMessageCount(conversations);
        return conversations;
      }
    }

    try {
      final queryParams = <String, String>{
        if (listingType != null && listingType.isNotEmpty)
          'listingType': listingType,
      };
      final response = await ApiService.timedGet(
        Uri.parse(
          '${ApiService.baseUrl}/conversations',
        ).replace(queryParameters: queryParams.isEmpty ? null : queryParams),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final conversations = data
            .map((json) => Conversation.fromJson(json))
            .toList();
        if (listingType == null || listingType.isEmpty) {
          CacheManager.conversations.set(conversations);
          _updateUnreadMessageCount(conversations);
        }
        return conversations;
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to load conversations.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load conversations.',
      );
      _logDebug('Error fetching conversations', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<int> refreshUnreadMessageCount({
    bool forceRefresh = true,
  }) async {
    if (!AuthService.isLoggedIn) {
      unreadMessageCount.value = 0;
      return 0;
    }

    try {
      final conversations = await getConversations(forceRefresh: forceRefresh);
      final totalUnread = conversations.fold<int>(
        0,
        (sum, conversation) => sum + conversation.unreadCount,
      );
      unreadMessageCount.value = totalUnread;
      return totalUnread;
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to refresh unread messages.',
      );
      _logDebug(
        'Error refreshing unread message count',
        appError.technicalMessage ?? e,
      );
      return unreadMessageCount.value;
    }
  }

  static Future<PaginatedConversations> getConversationsPaginated({
    int page = 0,
    int size = 10,
    bool forceRefresh = false,
    String? listingType,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final queryParams = <String, String>{
        'page': '$page',
        'size': '$size',
        if (listingType != null && listingType.isNotEmpty)
          'listingType': listingType,
      };
      final response = await ApiService.timedGet(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/paged',
        ).replace(queryParameters: queryParams),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        timeout: requestTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final conversationsJson =
              data['conversations'] as List<dynamic>? ?? [];
          final conversations = conversationsJson
              .map(
                (json) => Conversation.fromJson(json as Map<String, dynamic>),
              )
              .toList();

          final hasMore = data['hasMore'] as bool? ?? false;
          final pageNumber = (data['page'] as num?)?.toInt() ?? page;
          final pageSize = (data['size'] as num?)?.toInt() ?? size;
          final totalConversations =
              (data['totalConversations'] as num?)?.toInt() ?? 0;

          return PaginatedConversations(
            conversations: conversations,
            hasMore: hasMore,
            page: pageNumber,
            size: pageSize,
            totalConversations: totalConversations,
          );
        }
      }

      // Fallback when paginated endpoint is unavailable.
      if (response.statusCode == 404 || response.statusCode == 405) {
        final all = await getConversations(
          forceRefresh: forceRefresh || page > 0,
          listingType: listingType,
        );
        final start = page * size;
        if (start >= all.length) {
          return PaginatedConversations(
            conversations: const [],
            hasMore: false,
            page: page,
            size: size,
            totalConversations: all.length,
          );
        }

        final end = (start + size).clamp(0, all.length);
        return PaginatedConversations(
          conversations: all.sublist(start, end),
          hasMore: end < all.length,
          page: page,
          size: size,
          totalConversations: all.length,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load conversations.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load conversations.',
      );
      _logDebug(
        'Error fetching paginated conversations',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<Conversation> startConversation({
    int? rentalId,
    int? productId,
    String initialMessage = '',
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }
    if ((rentalId == null && productId == null) ||
        (rentalId != null && productId != null)) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'Invalid conversation request.',
      );
    }

    try {
      final payload = <String, dynamic>{
        if (rentalId != null) 'rentalId': rentalId,
        if (productId != null) 'productId': productId,
        if (initialMessage.trim().isNotEmpty) 'initialMessage': initialMessage,
      };
      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        CacheManager.conversations.clear();
        return Conversation.fromJson(jsonDecode(response.body));
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to start conversation.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to start conversation.',
      );
      _logDebug('Error starting conversation', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<QueuedConversationSendResult>
  startConversationAndSendMessageQueued({
    int? rentalId,
    int? productId,
    required String content,
    required String clientMessageId,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }
    if ((rentalId == null && productId == null) ||
        (rentalId != null && productId != null)) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'Invalid conversation request.',
      );
    }

    try {
      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/conversations/queue-start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          if (rentalId != null) 'rentalId': rentalId,
          if (productId != null) 'productId': productId,
          'content': content,
          'clientMessageId': clientMessageId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        CacheManager.conversations.clear();
        return QueuedConversationSendResult.fromJson(data);
      }

      await _handleAuthError(response.statusCode);
      if (_shouldFallbackToSyncSend(response.statusCode) ||
          response.statusCode == 404 ||
          response.statusCode == 405) {
        final conversation = await startConversation(
          rentalId: rentalId,
          productId: productId,
        );
        final messageResult = await sendMessageQueued(
          conversationId: conversation.id!,
          content: content,
          clientMessageId: clientMessageId,
        );
        return QueuedConversationSendResult(
          conversation: conversation,
          messageResult: messageResult,
        );
      }

      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to start conversation.',
      );
    } catch (e) {
      if (_canFallbackFromException(e)) {
        try {
          final conversation = await startConversation(
            rentalId: rentalId,
            productId: productId,
          );
          final messageResult = await sendMessageQueued(
            conversationId: conversation.id!,
            content: content,
            clientMessageId: clientMessageId,
          );
          return QueuedConversationSendResult(
            conversation: conversation,
            messageResult: messageResult,
          );
        } catch (_) {
          // Preserve original error mapping below.
        }
      }
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to start conversation.',
      );
      _logDebug(
        'Error queue-starting conversation',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<List<ChatMessage>> getMessages(
    int conversationId, {
    int page = 0,
    int limit = 10,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedGet(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/$conversationId/messages?page=$page&limit=$limit',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // New paginated response format
        if (data is Map && data.containsKey('messages')) {
          final List<dynamic> messages = data['messages'];
          return messages.map((json) => ChatMessage.fromJson(json)).toList();
        }
        // Fallback for old non-paginated format
        if (data is List) {
          return data.map((json) => ChatMessage.fromJson(json)).toList();
        }
        return [];
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to load messages.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load messages.',
      );
      _logDebug('Error fetching messages', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  /// Get messages with pagination info
  static Future<Map<String, dynamic>> getMessagesPaginated(
    int conversationId, {
    int page = 0,
    int limit = 10,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedGet(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/$conversationId/messages?page=$page&limit=$limit',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final List<dynamic> messagesJson = data['messages'] ?? [];
          final messages = messagesJson
              .map((json) => ChatMessage.fromJson(json))
              .toList();
          return {
            'messages': messages,
            'hasMore': data['hasMore'] ?? false,
            'totalMessages': data['totalMessages'] ?? 0,
            'page': data['page'] ?? 0,
          };
        }
        // Fallback for old format
        if (data is List) {
          return {
            'messages': data.map((json) => ChatMessage.fromJson(json)).toList(),
            'hasMore': false,
            'totalMessages': data.length,
            'page': 0,
          };
        }
        return {
          'messages': [],
          'hasMore': false,
          'totalMessages': 0,
          'page': 0,
        };
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to load messages.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load messages.',
      );
      _logDebug(
        'Error fetching paginated messages',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatMessage> sendMessage({
    required int conversationId,
    required String content,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedPost(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/$conversationId/messages',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'content': content}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return ChatMessage.fromJson(jsonDecode(response.body));
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to send message.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to send message.',
      );
      _logDebug('Error sending message', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<QueuedSendResult> sendMessageQueued({
    required int conversationId,
    required String content,
    required String clientMessageId,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedPost(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/$conversationId/messages/queue',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'content': content,
          'messageType': 'TEXT',
          'clientMessageId': clientMessageId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return QueuedSendResult.fromJson(data as Map<String, dynamic>);
      }

      await _handleAuthError(response.statusCode);

      // If queue endpoint is unavailable or temporarily unstable, fallback to
      // synchronous send so chat remains usable.
      if (_shouldFallbackToSyncSend(response.statusCode)) {
        final sent = await sendMessage(
          conversationId: conversationId,
          content: content,
        );
        return QueuedSendResult(
          status: 'SENT',
          mode: 'SYNC_FALLBACK',
          clientMessageId: clientMessageId,
          reason: 'QUEUE_ENDPOINT_UNAVAILABLE',
          message: sent,
        );
      }

      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to send message.',
      );
    } catch (e) {
      // Network errors on queue path should still try sync path once.
      if (_canFallbackFromException(e)) {
        try {
          final sent = await sendMessage(
            conversationId: conversationId,
            content: content,
          );
          return QueuedSendResult(
            status: 'SENT',
            mode: 'SYNC_FALLBACK',
            clientMessageId: clientMessageId,
            reason: 'QUEUE_EXCEPTION_FALLBACK',
            message: sent,
          );
        } catch (_) {
          // Keep original queue exception mapped below.
        }
      }
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to send message.',
      );
      _logDebug('Error sending queued message', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static bool _shouldFallbackToSyncSend(int statusCode) {
    switch (statusCode) {
      case 404:
      case 405:
      case 408:
      case 500:
      case 502:
      case 503:
      case 504:
        return true;
      default:
        return false;
    }
  }

  static bool _canFallbackFromException(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('timeout');
  }

  /// Upload a video and send it as a VIDEO message
  static Future<ChatMessage> sendVideoMessage({
    required int conversationId,
    required File videoFile,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiService.baseUrl}/conversations/$conversationId/messages/video',
        ),
      );
      request.headers['Authorization'] = 'Bearer ${AuthService.token}';
      request.files.add(
        await http.MultipartFile.fromPath('file', videoFile.path),
      );

      final streamedResponse = await request.send().timeout(
        ApiService.defaultRequestTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return ChatMessage.fromJson(jsonDecode(response.body));
      } else {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to send video.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to send video.',
      );
      _logDebug('Error sending video', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  /// Explicitly delete message media (admin/sender moderation action).
  static Future<void> deleteMessageMedia(int messageId) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedDelete(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/messages/$messageId/media',
        ),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode != 200) {
        await _handleAuthError(response.statusCode);
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to delete media.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to delete media.',
      );
      _logDebug('Error deleting media', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<void> markMessageMediaAccessed(int messageId) async {
    if (!AuthService.isLoggedIn) {
      return;
    }

    try {
      final response = await ApiService.timedPost(
        Uri.parse(
          '${ApiService.baseUrl}/conversations/messages/$messageId/media/accessed',
        ),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode != 200) {
        await _handleAuthError(response.statusCode);
      }
    } catch (_) {
      // Best effort only. Media access telemetry must not break playback/download UX.
    }
  }

  static Future<ChatSafetyStatus> getConversationSafetyStatus(
    int conversationId,
  ) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedGet(
        Uri.parse(
          '${ApiService.baseUrl}/chat/safety/conversations/$conversationId/status',
        ),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load chat safety status.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load chat safety status.',
      );
      _logDebug(
        'Error loading conversation chat safety status',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyStatus> updateConversationSafety(
    int conversationId, {
    bool? muted,
    bool? blocked,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }
    if (muted == null && blocked == null) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'No safety update was provided.',
      );
    }

    final payload = <String, dynamic>{};
    if (muted != null) payload['muted'] = muted;
    if (blocked != null) payload['blocked'] = blocked;

    try {
      final response = await ApiService.timedPut(
        Uri.parse(
          '${ApiService.baseUrl}/chat/safety/conversations/$conversationId',
        ),
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update chat safety settings.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to update chat safety settings.',
      );
      _logDebug(
        'Error updating conversation chat safety settings',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyStatus> clearConversationSafety(
    int conversationId,
  ) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedDelete(
        Uri.parse(
          '${ApiService.baseUrl}/chat/safety/conversations/$conversationId',
        ),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to clear chat safety settings.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to clear chat safety settings.',
      );
      _logDebug(
        'Error clearing conversation chat safety settings',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyStatus> getContactSafetyStatus(
    int targetUserId,
  ) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedGet(
        Uri.parse('${ApiService.baseUrl}/chat/safety/status/$targetUserId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load chat safety status.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load chat safety status.',
      );
      _logDebug(
        'Error loading chat safety status',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyStatus> updateContactSafety(
    int targetUserId, {
    bool? muted,
    bool? blocked,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }
    if (muted == null && blocked == null) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'No safety update was provided.',
      );
    }

    final payload = <String, dynamic>{};
    if (muted != null) payload['muted'] = muted;
    if (blocked != null) payload['blocked'] = blocked;

    try {
      final response = await ApiService.timedPut(
        Uri.parse('${ApiService.baseUrl}/chat/safety/contacts/$targetUserId'),
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update chat safety settings.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to update chat safety settings.',
      );
      _logDebug(
        'Error updating chat safety settings',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyStatus> clearContactSafety(int targetUserId) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    try {
      final response = await ApiService.timedDelete(
        Uri.parse('${ApiService.baseUrl}/chat/safety/contacts/$targetUserId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        return ChatSafetyStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to clear chat safety settings.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to clear chat safety settings.',
      );
      _logDebug(
        'Error clearing chat safety settings',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<ChatSafetyContactsPage> getSafetyContacts({
    int page = 0,
    int size = 20,
    ChatSafetyFilterMode mode = ChatSafetyFilterMode.all,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Please sign in to continue.',
      );
    }

    final modeValue = switch (mode) {
      ChatSafetyFilterMode.all => 'ALL',
      ChatSafetyFilterMode.muted => 'MUTED',
      ChatSafetyFilterMode.blocked => 'BLOCKED',
    };

    final uri = Uri.parse('${ApiService.baseUrl}/chat/safety/contacts').replace(
      queryParameters: {'page': '$page', 'size': '$size', 'mode': modeValue},
    );

    try {
      final response = await ApiService.timedGet(
        uri,
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        return ChatSafetyContactsPage.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      await _handleAuthError(response.statusCode);
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load muted/blocked contacts.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load muted/blocked contacts.',
      );
      _logDebug(
        'Error loading chat safety contacts',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static void _logDebug(String message, Object? details) {
    if (!kDebugMode) return;
    debugPrint('$message: $details');
  }

  static void _updateUnreadMessageCount(List<Conversation> conversations) {
    unreadMessageCount.value = conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );
  }
}
