export 'package:http/http.dart' hide get, post, put, delete, patch;

import 'dart:convert';
import 'package:http/http.dart' as original_http;
import 'package:http_certificate_pinning/http_certificate_pinning.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'auth_service.dart';

import 'dart:async';
import 'dart:io';

// SHA-256 public key hash for api.ishinadwelly.com
final List<String> _allowedSHAFingerprints = [
  'd/wIGVX2nKc/X7Gjz7EQSrs/q+fYCoaT+CeOhZokvfk=',
];

// Reusable secure client
final original_http.Client _secureClient = SecureHttpClient.build(
  _allowedSHAFingerprints,
);

Future<original_http.Response> _executeWithRetry(
  Uri url,
  Future<original_http.Response> Function(Map<String, String>? headers) requestFn,
  Map<String, String>? originalHeaders,
) async {
  original_http.Response response;
  
  final enhancedHeaders = Map<String, String>.from(originalHeaders ?? {});
  
  try {
    // Append Firebase AppCheck token to all outbound requests
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (appCheckToken != null) {
      enhancedHeaders['X-Firebase-AppCheck'] = appCheckToken;
    }
  } catch (e) {
    print('[AppCheck] Failed to fetch token: $e');
  }

  try {
    // print('[API REQUEST] -> ${url.toString()}');
    response = await requestFn(enhancedHeaders);
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
      response = await requestFn(enhancedHeaders);
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
      if (enhancedHeaders.containsKey('Authorization') ||
          enhancedHeaders.containsKey('authorization')) {
        enhancedHeaders.remove('Authorization');
        enhancedHeaders.remove('authorization');
        enhancedHeaders['Authorization'] = 'Bearer ${AuthService.token}';
      }
      response = await requestFn(enhancedHeaders);
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
    (h) => _secureClient.get(url, headers: h),
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
    (h) => _secureClient.post(url, headers: h, body: body, encoding: encoding),
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
    (h) => _secureClient.put(url, headers: h, body: body, encoding: encoding),
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
    (h) => _secureClient.delete(url, headers: h, body: body, encoding: encoding),
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
    (h) => _secureClient.patch(url, headers: h, body: body, encoding: encoding),
    headers,
  );
}
