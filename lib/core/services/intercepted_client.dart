export 'package:http/http.dart' hide get, post, put, delete, patch;

import 'dart:convert';
import 'package:http/http.dart' as original_http;
import 'auth_service.dart';

Future<original_http.Response> _executeWithRetry(
  Future<original_http.Response> Function(Map<String, String>? headers) requestFn,
  Map<String, String>? originalHeaders,
) async {
  original_http.Response response = await requestFn(originalHeaders);
  if (response.statusCode == 401 && AuthService.token != null) {
    // Try to refresh token
    final success = await AuthService.refreshAuthToken();
    if (success && AuthService.token != null) {
      // Retry request with new token
      final newHeaders = Map<String, String>.from(originalHeaders ?? {});
      if (newHeaders.containsKey('Authorization') || newHeaders.containsKey('authorization')) {
        newHeaders.remove('Authorization');
        newHeaders.remove('authorization');
        newHeaders['Authorization'] = 'Bearer ${AuthService.token}';
      }
      response = await requestFn(newHeaders);
    }
  }
  return response;
}

Future<original_http.Response> get(Uri url, {Map<String, String>? headers}) async {
  return _executeWithRetry((h) => original_http.get(url, headers: h), headers);
}

Future<original_http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return _executeWithRetry((h) => original_http.post(url, headers: h, body: body, encoding: encoding), headers);
}

Future<original_http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return _executeWithRetry((h) => original_http.put(url, headers: h, body: body, encoding: encoding), headers);
}

Future<original_http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return _executeWithRetry((h) => original_http.delete(url, headers: h, body: body, encoding: encoding), headers);
}

Future<original_http.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return _executeWithRetry((h) => original_http.patch(url, headers: h, body: body, encoding: encoding), headers);
}
