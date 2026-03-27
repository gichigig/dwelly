import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../errors/app_error.dart';
import '../errors/error_mapper.dart';

class ApiService {
  static final Map<String, _CachedGetEntry> _getCache = {};
  static final Map<String, Future<http.Response>> _inFlightGets = {};
  static final Map<String, String> _etagByKey = {};
  static const Duration defaultRequestTimeout = Duration(seconds: 15);

  static const Map<String, String> _hostAliases = {
    // Common typo fallback to keep app usable if the wrong host is provided.
    'api.billygichidev.me': 'api.billygichigidev.me',
  };

  // Optional Cloudflare tunnel URL passed via --dart-define.
  // Example: flutter run --dart-define=CLOUDFLARE_URL=https://xxxx.trycloudflare.com
  static const String _cloudflareUrl = String.fromEnvironment(
    'CLOUDFLARE_URL',
    defaultValue: '',
  );

  // Use 10.0.2.2 for Android emulator, localhost for web/iOS simulator
  static String get baseUrl {
    // Use runtime URL if set (for physical devices)
    if (_runtimeUrl != null && _runtimeUrl!.isNotEmpty) {
      return _toApiBase(_runtimeUrl!);
    }

    // If Cloudflare URL is set, use it (for physical devices)
    if (_cloudflareUrl.isNotEmpty) {
      return _toApiBase(_cloudflareUrl);
    }

    return _defaultBaseUrl;
  }

  // Helper method to update the base URL at runtime (useful for settings)
  static String? _runtimeUrl;

  static void setCloudflareUrl(String url) {
    _runtimeUrl = url.trim();
  }

  static void clearRuntimeUrl() {
    _runtimeUrl = null;
  }

  static String get effectiveBaseUrl {
    if (_runtimeUrl != null && _runtimeUrl!.isNotEmpty) {
      return _toApiBase(_runtimeUrl!);
    }
    return baseUrl;
  }

  static String _toApiBase(String rawUrl) {
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) {
      return _defaultBaseUrl;
    }

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }

    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    try {
      final uri = Uri.parse(normalized);
      if (!uri.hasScheme || uri.host.isEmpty) {
        return _defaultBaseUrl;
      }

      final correctedHost = _hostAliases[uri.host.toLowerCase()];
      if (correctedHost != null && correctedHost != uri.host) {
        final correctedUri = uri.replace(host: correctedHost);
        normalized = correctedUri.toString();
        if (normalized.endsWith('/')) {
          normalized = normalized.substring(0, normalized.length - 1);
        }
      }
    } catch (_) {
      return _defaultBaseUrl;
    }

    if (normalized.endsWith('/api')) {
      return normalized;
    }
    return '$normalized/api';
  }

  static String get _defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:8080/api';
    }
    // Android emulator uses 10.0.2.2 to reach host's localhost.
    return 'http://10.0.2.2:8080/api';
  }

  /// Helper method to get HTTP headers for API requests
  static Map<String, String> getHeaders({String? token}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<http.Response> timedGet(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = defaultRequestTimeout,
  }) {
    return http.get(uri, headers: headers).timeout(timeout);
  }

  static Future<http.Response> timedPost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = defaultRequestTimeout,
  }) {
    return http
        .post(uri, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }

  static Future<http.Response> timedPut(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = defaultRequestTimeout,
  }) {
    return http
        .put(uri, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }

  static Future<http.Response> timedPatch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = defaultRequestTimeout,
  }) {
    return http
        .patch(uri, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }

  static Future<http.Response> timedDelete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = defaultRequestTimeout,
  }) {
    return http
        .delete(uri, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }

  // Helper to parse JSON
  static dynamic parseJson(String body) {
    return jsonDecode(body);
  }

  // Helper to encode JSON
  static String encodeJson(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  /// Convert an HTTP response into a user-safe typed error.
  static AppError parseHttpError(
    http.Response response, {
    String fallbackMessage = 'Something went wrong. Please try again.',
  }) {
    return ErrorMapper.fromHttpResponse(
      response,
      fallbackMessage: fallbackMessage,
    );
  }

  /// Convert any thrown exception into a user-safe typed error.
  static AppError parseException(
    Object error, {
    String fallbackMessage = 'Something went wrong. Please try again.',
  }) {
    return ErrorMapper.fromException(error, fallbackMessage: fallbackMessage);
  }

  /// Cached GET with request coalescing + ETag revalidation.
  static Future<http.Response> cachedGet(
    Uri uri, {
    Map<String, String>? headers,
    Duration ttl = const Duration(seconds: 30),
    Duration staleWhileRevalidate = const Duration(seconds: 90),
    Duration requestTimeout = defaultRequestTimeout,
  }) async {
    final requestHeaders = <String, String>{'Accept': 'application/json'};
    if (headers != null) {
      requestHeaders.addAll(headers);
    }

    final key = _cacheKeyFor(uri, requestHeaders);
    final cached = _getCache[key];

    if (cached != null && cached.isFresh) {
      return cached.asResponse(extraHeaders: {'x-local-cache': 'HIT'});
    }

    if (cached != null && cached.isWithinStaleWindow) {
      final inFlight = _inFlightGets[key];
      if (inFlight == null) {
        final refresh = _fetchAndCache(
          key: key,
          uri: uri,
          headers: requestHeaders,
          ttl: ttl,
          staleWhileRevalidate: staleWhileRevalidate,
          staleFallback: cached,
          requestTimeout: requestTimeout,
        ).whenComplete(() => _inFlightGets.remove(key));
        _inFlightGets[key] = refresh;
        unawaited(refresh);
      }
      return cached.asResponse(extraHeaders: {'x-local-cache': 'STALE'});
    }

    final existing = _inFlightGets[key];
    if (existing != null) {
      return existing;
    }

    final request = _fetchAndCache(
      key: key,
      uri: uri,
      headers: requestHeaders,
      ttl: ttl,
      staleWhileRevalidate: staleWhileRevalidate,
      staleFallback: cached,
      requestTimeout: requestTimeout,
    ).whenComplete(() => _inFlightGets.remove(key));

    _inFlightGets[key] = request;
    return request;
  }

  static void invalidateCachedGetByPath(String pathSegment) {
    if (pathSegment.trim().isEmpty) return;
    final needle = pathSegment.toLowerCase();
    final keysToRemove = _getCache.keys
        .where((key) => key.toLowerCase().contains(needle))
        .toList();
    for (final key in keysToRemove) {
      _getCache.remove(key);
      _etagByKey.remove(key);
      _inFlightGets.remove(key);
    }
  }

  static void clearCachedGets() {
    _getCache.clear();
    _etagByKey.clear();
    _inFlightGets.clear();
  }

  static Future<http.Response> _fetchAndCache({
    required String key,
    required Uri uri,
    required Map<String, String> headers,
    required Duration ttl,
    required Duration staleWhileRevalidate,
    required Duration requestTimeout,
    _CachedGetEntry? staleFallback,
  }) async {
    final requestHeaders = <String, String>{}..addAll(headers);
    final etag = _etagByKey[key];
    if (etag != null && etag.isNotEmpty) {
      requestHeaders['If-None-Match'] = etag;
    }

    try {
      final response = await timedGet(
        uri,
        headers: requestHeaders,
        timeout: requestTimeout,
      );

      if (response.statusCode == 304 && staleFallback != null) {
        staleFallback.touch(
          ttl: ttl,
          staleWhileRevalidate: staleWhileRevalidate,
        );
        return staleFallback.asResponse(
          extraHeaders: {'x-local-cache': 'REVALIDATED'},
        );
      }

      if (response.statusCode == 200) {
        final responseEtag = response.headers['etag'];
        if (responseEtag != null && responseEtag.isNotEmpty) {
          _etagByKey[key] = responseEtag;
        }
        _getCache[key] = _CachedGetEntry.fromResponse(
          response,
          ttl: ttl,
          staleWhileRevalidate: staleWhileRevalidate,
        );
      }

      if (response.statusCode >= 500 &&
          staleFallback != null &&
          staleFallback.isWithinStaleWindow) {
        return staleFallback.asResponse(
          extraHeaders: {'x-local-cache': 'STALE'},
        );
      }

      return response;
    } catch (_) {
      if (staleFallback != null && staleFallback.isWithinStaleWindow) {
        return staleFallback.asResponse(
          extraHeaders: {'x-local-cache': 'STALE'},
        );
      }
      rethrow;
    }
  }

  static String _cacheKeyFor(Uri uri, Map<String, String> headers) {
    final auth = headers['Authorization'];
    final authScope = auth == null || auth.isEmpty ? 'anon' : auth.hashCode;
    return '${uri.toString()}|$authScope';
  }
}

class _CachedGetEntry {
  final String body;
  final int statusCode;
  final Map<String, String> headers;
  DateTime freshUntil;
  DateTime staleUntil;

  _CachedGetEntry({
    required this.body,
    required this.statusCode,
    required this.headers,
    required this.freshUntil,
    required this.staleUntil,
  });

  factory _CachedGetEntry.fromResponse(
    http.Response response, {
    required Duration ttl,
    required Duration staleWhileRevalidate,
  }) {
    final now = DateTime.now();
    return _CachedGetEntry(
      body: response.body,
      statusCode: response.statusCode,
      headers: Map<String, String>.from(response.headers),
      freshUntil: now.add(ttl),
      staleUntil: now.add(ttl + staleWhileRevalidate),
    );
  }

  bool get isFresh => DateTime.now().isBefore(freshUntil);

  bool get isWithinStaleWindow => DateTime.now().isBefore(staleUntil);

  void touch({required Duration ttl, required Duration staleWhileRevalidate}) {
    final now = DateTime.now();
    freshUntil = now.add(ttl);
    staleUntil = now.add(ttl + staleWhileRevalidate);
  }

  http.Response asResponse({Map<String, String>? extraHeaders}) {
    final mergedHeaders = <String, String>{}..addAll(headers);
    if (extraHeaders != null) {
      mergedHeaders.addAll(extraHeaders);
    }
    return http.Response(body, statusCode, headers: mergedHeaders);
  }
}
