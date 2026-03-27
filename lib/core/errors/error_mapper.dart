import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_error.dart';

class ErrorMapper {
  static AppError fromHttpResponse(
    http.Response response, {
    String fallbackMessage = 'Something went wrong. Please try again.',
  }) {
    final statusCode = response.statusCode;
    final payload = _parsePayload(response.body);
    final code = _extractCode(payload);
    final rawMessage = _extractMessage(payload);
    final safeMessage = _safeMessage(rawMessage);

    if (statusCode == 401) {
      return const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Your session expired. Please sign in again.',
        statusCode: 401,
        retryable: true,
      );
    }
    if (statusCode == 403) {
      if (code == 'CHAT_CONTACT_BLOCKED') {
        return const AppError(
          code: AppErrorCode.forbidden,
          message:
              'You cannot message this contact because one of you has blocked the other.',
          statusCode: 403,
        );
      }
      return const AppError(
        code: AppErrorCode.forbidden,
        message: 'You do not have permission to do that.',
        statusCode: 403,
      );
    }
    if (statusCode == 404) {
      return const AppError(
        code: AppErrorCode.notFound,
        message: 'That item is no longer available.',
        statusCode: 404,
      );
    }
    if (statusCode == 429) {
      return const AppError(
        code: AppErrorCode.rateLimited,
        message: 'Too many attempts. Please wait and try again.',
        statusCode: 429,
        retryable: true,
      );
    }
    if (statusCode == 400 || statusCode == 422) {
      final validationMessage = _extractValidationMessage(payload);
      return AppError(
        code: AppErrorCode.validation,
        message:
            validationMessage ??
            safeMessage ??
            'Please check your input and try again.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 530) {
      return AppError.network(
        technicalMessage: 'HTTP 530: ${_compactTechnicalBody(response.body)}',
      );
    }
    if (statusCode >= 500) {
      return AppError.server(
        statusCode: statusCode,
        message: 'Something went wrong. Please try again.',
        technicalMessage:
            'HTTP $statusCode: ${_compactTechnicalBody(response.body)}',
      );
    }
    if (statusCode >= 200 && statusCode < 300) {
      return AppError(
        code: AppErrorCode.unknown,
        message: safeMessage ?? fallbackMessage,
        statusCode: statusCode,
      );
    }

    return AppError(
      code: AppErrorCode.unknown,
      message: safeMessage ?? fallbackMessage,
      statusCode: statusCode,
    );
  }

  static AppError fromException(
    Object error, {
    String fallbackMessage = 'Something went wrong. Please try again.',
  }) {
    if (error is AppError) {
      return error;
    }

    if (error is SocketException || error is HttpException) {
      return AppError.network(technicalMessage: error.toString());
    }

    if (error is TimeoutException) {
      return AppError.timeout(technicalMessage: error.toString());
    }

    final raw = error.toString().trim();
    final lower = raw.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('clientexception')) {
      return AppError.network(technicalMessage: raw);
    }

    if (lower.contains('timeout')) {
      return AppError.timeout(technicalMessage: raw);
    }

    if (lower.contains('session expired')) {
      return const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Your session expired. Please sign in again.',
        retryable: true,
      );
    }

    if (lower.contains('530')) {
      return AppError.network(technicalMessage: raw);
    }

    final safeMessage = _safeMessage(raw);
    return AppError(
      code: AppErrorCode.unknown,
      message: safeMessage ?? fallbackMessage,
      technicalMessage: _compactTechnicalBody(raw),
    );
  }

  static bool isSilent(Object error) {
    final appError = error is AppError ? error : fromException(error);
    return appError.silent;
  }

  static String userMessage(
    Object error, {
    String fallbackMessage = 'Something went wrong. Please try again.',
  }) {
    return fromException(error, fallbackMessage: fallbackMessage).message;
  }

  static Map<String, dynamic>? _parsePayload(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static String? _extractMessage(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final message = payload['message']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
    final error = payload['error']?.toString().trim();
    if (error != null && error.isNotEmpty) return error;
    return null;
  }

  static String? _extractCode(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final code = payload['code']?.toString().trim();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  static String? _extractValidationMessage(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final errors = payload['errors'];
    if (errors is Map<String, dynamic> && errors.isNotEmpty) {
      final first = errors.entries.first;
      final message = first.value.toString().trim();
      if (message.isNotEmpty) return message;
    } else if (errors is Map && errors.isNotEmpty) {
      final entry = errors.entries.first;
      final message = entry.value.toString().trim();
      if (message.isNotEmpty) return message;
    }
    return null;
  }

  static String? _safeMessage(String? raw) {
    if (raw == null) return null;
    var message = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (message.isEmpty) return null;
    final lower = message.toLowerCase();

    final looksSensitive =
        lower.contains('platformexception(') ||
        lower.contains('java.lang') ||
        lower.contains('org.springframework') ||
        lower.contains('stacktrace') ||
        lower.contains('sql') ||
        lower.contains('hibernate') ||
        lower.contains('insert into') ||
        lower.contains('select ') ||
        lower.contains('nullpointerexception') ||
        lower.contains('renderflex') ||
        lower.contains('globalkey') ||
        lower.contains('<html') ||
        lower.contains('<!doctype html');

    if (looksSensitive) return null;
    return message;
  }

  static String _compactTechnicalBody(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    final lower = trimmed.toLowerCase();
    if (lower.contains('<html') || lower.contains('<!doctype html')) {
      return '<html-error-body-suppressed>';
    }
    const maxLen = 300;
    if (trimmed.length <= maxLen) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLen)}...';
  }
}
