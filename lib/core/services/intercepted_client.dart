export 'package:http/http.dart' hide get, post, put, delete, patch;

import 'dart:convert';
import 'package:http/http.dart' as original_http;
import 'auth_service.dart';

import 'dart:async';
import 'dart:io';

Future<original_http.Response> _executeWithRetry(
  Uri url,
  Future<original_http.Response> Function(Map<String, String>? headers)
  requestFn,
  Map<String, String>? originalHeaders,
) async {
  original_http.Response response;
  try {
    // print('[API REQUEST] -> ${url.toString()}');
    response = await requestFn(originalHeaders);
    // print('[API RESPONSE] <- ${response.statusCode} ${url.toString()}');
  } catch (e, stack) {
    print('[API ERROR] Request failed: ${url.toString()}');
    print('[API ERROR] Exception: $e');
    print('[API ERROR] Stack: $stack');
    // Automatically retry once for common network/connection hiccups (e.g. emulator waking up)
    final errorStr = e.toString().toLowerCase();
    if (e is SocketException ||
        e is TimeoutException ||
        errorStr.contains('connection refused') ||
        errorStr.contains('clientexception') ||
        errorStr.contains('failed host lookup')) {
      print('[API RETRY] Retrying ${url.toString()} in 1s...');
      await Future.delayed(const Duration(milliseconds: 1000));
      response = await requestFn(originalHeaders);
    } else {
      rethrow;
    }
  }

  final isAuthPath =
      url.path.endsWith('/auth/refresh') ||
      url.path.endsWith('/auth/logout') ||
      url.path.endsWith('/auth/login') ||
      url.path.endsWith('/auth/login/init') ||
      url.path.endsWith('/auth/register');

  if (response.statusCode == 401 && AuthService.token != null && !isAuthPath) {
    // Try to refresh token
    final success = await AuthService.refreshAuthToken();
    if (success && AuthService.token != null) {
      // Retry request with new token
      final newHeaders = Map<String, String>.from(originalHeaders ?? {});
      if (newHeaders.containsKey('Authorization') ||
          newHeaders.containsKey('authorization')) {
        newHeaders.remove('Authorization');
        newHeaders.remove('authorization');
        newHeaders['Authorization'] = 'Bearer ${AuthService.token}';
      }
      response = await requestFn(newHeaders);
    }
  }
  return response;
}

Future<original_http.Response> get(
  Uri url, {
  Map<String, String>? headers,
}) async {
  return _executeWithRetry(
    url,
    (h) => original_http.get(url, headers: h),
    headers,
  );
}

Future<original_http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _executeWithRetry(
    url,
    (h) => original_http.post(url, headers: h, body: body, encoding: encoding),
    headers,
  );
}

Future<original_http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _executeWithRetry(
    url,
    (h) => original_http.put(url, headers: h, body: body, encoding: encoding),
    headers,
  );
}

Future<original_http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _executeWithRetry(
    url,
    (h) =>
        original_http.delete(url, headers: h, body: body, encoding: encoding),
    headers,
  );
}

Future<original_http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  return _executeWithRetry(
    url,
    (h) => original_http.patch(url, headers: h, body: body, encoding: encoding),
    headers,
  );
}
