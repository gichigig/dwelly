import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/advertisement.dart';
import 'api_service.dart';

/// Display configuration for ads
class AdDisplayConfig {
  final String
  rentalFeedIntervals; // Comma-separated positions e.g., "5,10,15,20"
  final bool launchAdEnabled;
  final bool filterAdEnabled;
  final bool sponsoredAdsEnabled;
  final int launchAdCooldownMinutes;
  final bool launchAdBreakEnabled;
  final int launchAdBreakCount;
  final bool launchAdFirstUnskippable;
  final bool launchAdResumeEnabled;
  final int launchAdResumeCooldownMinutes;
  final int launchAdResumeMinBackgroundSeconds;
  final bool marketplaceFeedAdEnabled;
  final bool marketplaceDetailAdEnabled;
  final bool marketplaceSearchAdEnabled;
  final String marketplaceFeedIntervals;

  AdDisplayConfig({
    this.rentalFeedIntervals = '5,10,15,20',
    this.launchAdEnabled = true,
    this.filterAdEnabled = true,
    this.sponsoredAdsEnabled = true,
    this.launchAdCooldownMinutes = 30,
    this.launchAdBreakEnabled = true,
    this.launchAdBreakCount = 2,
    this.launchAdFirstUnskippable = true,
    this.launchAdResumeEnabled = true,
    this.launchAdResumeCooldownMinutes = 15,
    this.launchAdResumeMinBackgroundSeconds = 30,
    this.marketplaceFeedAdEnabled = true,
    this.marketplaceDetailAdEnabled = true,
    this.marketplaceSearchAdEnabled = true,
    this.marketplaceFeedIntervals = '4,9,14',
  });

  factory AdDisplayConfig.fromJson(Map<String, dynamic> json) {
    return AdDisplayConfig(
      rentalFeedIntervals: json['rentalFeedIntervals'] ?? '5,10,15,20',
      launchAdEnabled: json['launchAdEnabled'] ?? true,
      filterAdEnabled: json['filterAdEnabled'] ?? true,
      sponsoredAdsEnabled: json['sponsoredAdsEnabled'] ?? true,
      launchAdCooldownMinutes: json['launchAdCooldownMinutes'] ?? 30,
      launchAdBreakEnabled: json['launchAdBreakEnabled'] ?? true,
      launchAdBreakCount: json['launchAdBreakCount'] ?? 2,
      launchAdFirstUnskippable: json['launchAdFirstUnskippable'] ?? true,
      launchAdResumeEnabled: json['launchAdResumeEnabled'] ?? true,
      launchAdResumeCooldownMinutes:
          json['launchAdResumeCooldownMinutes'] ?? 15,
      launchAdResumeMinBackgroundSeconds:
          json['launchAdResumeMinBackgroundSeconds'] ?? 30,
      marketplaceFeedAdEnabled: json['marketplaceFeedAdEnabled'] ?? true,
      marketplaceDetailAdEnabled: json['marketplaceDetailAdEnabled'] ?? true,
      marketplaceSearchAdEnabled: json['marketplaceSearchAdEnabled'] ?? true,
      marketplaceFeedIntervals: json['marketplaceFeedIntervals'] ?? '4,9,14',
    );
  }

  /// Get list of feed positions where ads should appear
  List<int> get feedPositions {
    return rentalFeedIntervals
        .split(',')
        .map((s) => int.tryParse(s.trim()) ?? 5)
        .toList();
  }

  List<int> get marketplaceFeedPositions {
    return marketplaceFeedIntervals
        .split(',')
        .map((s) => int.tryParse(s.trim()) ?? 4)
        .toList();
  }
}

class AdBreakPolicy {
  final String skipMode;
  final int skipDelaySeconds;

  const AdBreakPolicy({
    this.skipMode = 'FIRST_LOCK_THEN_DELAYED_SKIP',
    this.skipDelaySeconds = 5,
  });

  factory AdBreakPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdBreakPolicy();
    return AdBreakPolicy(
      skipMode: json['skipMode']?.toString() ?? 'FIRST_LOCK_THEN_DELAYED_SKIP',
      skipDelaySeconds: (json['skipDelaySeconds'] as num?)?.toInt() ?? 5,
    );
  }
}

class AdBreakPayload {
  final bool available;
  final List<Advertisement> ads;
  final AdBreakPolicy policy;
  final String? breakId;

  const AdBreakPayload({
    required this.available,
    required this.ads,
    required this.policy,
    this.breakId,
  });

  factory AdBreakPayload.fromJson(Map<String, dynamic> json) {
    final rawAds = (json['ads'] as List?) ?? const [];
    return AdBreakPayload(
      available: json['available'] == true,
      ads: rawAds
          .whereType<Map>()
          .map((entry) => Advertisement.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList(),
      policy: AdBreakPolicy.fromJson(
        json['policy'] is Map<String, dynamic>
            ? json['policy'] as Map<String, dynamic>
            : null,
      ),
      breakId: json['breakId']?.toString(),
    );
  }
}

/// Service for managing advertisements with caching support
class AdService {
  static String get _baseUrl =>
      ApiService.baseUrl; // Use shared API service URL
  static const String _cacheKeyPrefix = 'ads_cache_';
  static const String _configCacheKey = 'ad_display_config';
  static const String _targetedCacheKeyPrefix = 'ads_targeted_cache_';
  static const String _breakCacheKeyPrefix = 'ads_break_cache_';
  static const String _lastLaunchAdKey = 'last_launch_ad_time';
  static const String _lastResumeAdKey = 'last_resume_ad_time';
  static const String _lastBackgroundAtKey = 'last_background_at';
  static const Duration _cacheExpiry = Duration(hours: 1);
  static const Duration _staleAllowed = Duration(
    hours: 24,
  ); // Show stale data for up to 24h
  static const Duration _targetedFreshExpiry = Duration(minutes: 15);
  static const Duration _targetedStaleAllowed = Duration(hours: 24);
  static const Duration _breakFreshExpiry = Duration(minutes: 10);
  static const Duration _breakStaleAllowed = Duration(hours: 12);
  static const Duration _targetedRequestTimeout = Duration(milliseconds: 2500);
  static const Duration _breakRequestTimeout = Duration(milliseconds: 2500);
  static const Duration _configRequestTimeout = Duration(seconds: 3);

  static AdService? _instance;
  final SharedPreferences _prefs;
  AdDisplayConfig? _cachedConfig;
  Duration _lastAdRequestLatency = Duration.zero;
  int _consecutiveAdTimeouts = 0;

  AdService._(this._prefs);

  /// Get singleton instance
  static Future<AdService> getInstance() async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = AdService._(prefs);
    }
    return _instance!;
  }

  /// Get ads for a specific placement with caching
  Future<List<Advertisement>> getAdsForPlacement(
    AdPlacement placement, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$_cacheKeyPrefix${placement.name}';
    final timestampKey = '${cacheKey}_timestamp';

    // Check cache first unless force refresh
    if (!forceRefresh) {
      final cached = await _getCachedAds(cacheKey, timestampKey);
      if (cached != null) return cached;
    }

    try {
      // Fetch from API
      final response = await http
          .get(Uri.parse('$_baseUrl/ads/public?placement=${placement.name}'))
          .timeout(_configRequestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawList = data is List
            ? data
            : (data is Map<String, dynamic>
                      ? data['content'] as List?
                      : null) ??
                  <dynamic>[];
        final ads = rawList
            .map((json) => Advertisement.fromJson(json as Map<String, dynamic>))
            .where((ad) => ad.shouldDisplay)
            .toList();

        // Sort by priority (higher first)
        ads.sort((a, b) => b.priority.compareTo(a.priority));

        // Cache the results
        await _cacheAds(cacheKey, timestampKey, ads);
        _markAdNetworkSuccess();

        return ads;
      }

      // On error, try to return stale cache
      _markAdNetworkFailure();
      return await _getStaleCache(cacheKey, timestampKey) ?? [];
    } catch (e) {
      // On network error, return stale cache if available
      _markAdNetworkFailure();
      return await _getStaleCache(cacheKey, timestampKey) ?? [];
    }
  }

  /// Get a single ad by ID
  Future<Advertisement?> getAd(int id) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/ads/public/$id'))
          .timeout(_configRequestTimeout);

      if (response.statusCode == 200) {
        return Advertisement.fromJson(jsonDecode(response.body));
      }
      _markAdNetworkFailure();
      return null;
    } catch (e) {
      _markAdNetworkFailure();
      return null;
    }
  }

  /// Record an ad impression
  Future<void> recordImpression(int adId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/ads/$adId/impression'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail - don't disrupt UX for analytics
    }
  }

  /// Record an ad click
  Future<void> recordClick(int adId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/ads/$adId/click'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail - don't disrupt UX for analytics
    }
  }

  /// Record video view start
  Future<void> recordVideoView(int adId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/ads/$adId/video-view'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail
    }
  }

  /// Record video completion
  Future<void> recordVideoCompletion(int adId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/ads/$adId/video-complete'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail
    }
  }

  /// Record ad skip
  Future<void> recordSkip(int adId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/ads/$adId/skip'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail
    }
  }

  /// Record detailed analytics event
  Future<void> recordAnalyticsEvent({
    required int adId,
    required String eventType,
    String? county,
    String? constituency,
    String? placement,
    int? videoWatchedSeconds,
    String? breakId,
    int? breakStepIndex,
  }) async {
    try {
      final deviceType = Platform.isAndroid
          ? 'ANDROID'
          : (Platform.isIOS ? 'IOS' : 'WEB');
      await http
          .post(
            Uri.parse('$_baseUrl/ads/$adId/analytics'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'eventType': eventType,
              'county': county,
              'constituency': constituency,
              'deviceType': deviceType,
              'placement': placement,
              if (videoWatchedSeconds != null)
                'videoWatchedSeconds': videoWatchedSeconds,
              if (breakId != null) 'breakId': breakId,
              if (breakStepIndex != null) 'breakStepIndex': breakStepIndex,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Silently fail
    }
  }

  /// Get location-targeted ad for a specific placement
  Future<Advertisement?> getTargetedAd(
    AdPlacement placement, {
    String? county,
    String? constituency,
    String? mediaHint,
  }) async {
    final resolvedMediaHint = mediaHint ?? _resolveMediaHint();
    final cacheKey = _targetedCacheKey(
      placement: placement,
      county: county,
      constituency: constituency,
      mediaHint: resolvedMediaHint,
    );
    final timestampKey = '${cacheKey}_timestamp';

    final cached = await _getCachedTargetedAd(cacheKey, timestampKey);
    if (cached != null) {
      // Stale-while-revalidate.
      _refreshTargetedAdInBackground(
        placement: placement,
        county: county,
        constituency: constituency,
        mediaHint: resolvedMediaHint,
        cacheKey: cacheKey,
        timestampKey: timestampKey,
      );
      return cached;
    }

    final fresh = await _fetchTargetedAdFromApi(
      placement: placement,
      county: county,
      constituency: constituency,
      mediaHint: resolvedMediaHint,
    );
    if (fresh != null) {
      await _cacheTargetedAd(cacheKey, timestampKey, fresh);
      return fresh;
    }

    return _getStaleTargetedAd(cacheKey, timestampKey);
  }

  Future<Map<AdPlacement, Advertisement?>> getTargetedAdsBatch(
    List<AdPlacement> placements, {
    String? county,
    String? constituency,
    String? mediaHint,
  }) async {
    final resolvedMediaHint = mediaHint ?? _resolveMediaHint();
    final placementsCsv = placements.map((p) => p.name).join(',');
    final queryParams = <String, String>{
      'placements': placementsCsv,
      if (county != null && county.isNotEmpty) 'county': county,
      if (constituency != null && constituency.isNotEmpty)
        'constituency': constituency,
      'mediaHint': resolvedMediaHint,
    };
    final uri = Uri.parse(
      '$_baseUrl/ads/public/targeted/batch',
    ).replace(queryParameters: queryParams);

    final fallback = <AdPlacement, Advertisement?>{};
    for (final placement in placements) {
      fallback[placement] = await getTargetedAd(
        placement,
        county: county,
        constituency: constituency,
        mediaHint: resolvedMediaHint,
      );
    }

    final startedAt = DateTime.now();
    try {
      final response = await http.get(uri).timeout(_targetedRequestTimeout);
      _lastAdRequestLatency = DateTime.now().difference(startedAt);
      if (response.statusCode != 200) {
        _markAdNetworkFailure();
        return fallback;
      }

      final data = jsonDecode(response.body);
      final placementsMap = data['placements'] as Map<String, dynamic>? ?? {};
      final result = <AdPlacement, Advertisement?>{};
      for (final placement in placements) {
        final entry = placementsMap[placement.name];
        if (entry is Map<String, dynamic> &&
            entry['available'] == true &&
            entry['ad'] is Map<String, dynamic>) {
          final ad = Advertisement.fromJson(entry['ad']);
          result[placement] = ad;
          final key = _targetedCacheKey(
            placement: placement,
            county: county,
            constituency: constituency,
            mediaHint: resolvedMediaHint,
          );
          await _cacheTargetedAd(key, '${key}_timestamp', ad);
        } else {
          result[placement] = null;
        }
      }
      _markAdNetworkSuccess();
      return result;
    } catch (_) {
      _markAdNetworkFailure();
      return fallback;
    }
  }

  Future<AdBreakPayload?> getAdBreak(
    AdPlacement placement, {
    int count = 2,
    String? county,
    String? constituency,
    String? mediaHint,
  }) async {
    final resolvedMediaHint = mediaHint ?? _resolveMediaHint();
    final cacheKey = _breakCacheKey(
      placement: placement,
      county: county,
      constituency: constituency,
      mediaHint: resolvedMediaHint,
      count: count,
    );
    final timestampKey = '${cacheKey}_timestamp';

    final cached = await _getCachedBreakPayload(cacheKey, timestampKey);
    if (cached != null) {
      _refreshBreakInBackground(
        placement: placement,
        count: count,
        county: county,
        constituency: constituency,
        mediaHint: resolvedMediaHint,
        cacheKey: cacheKey,
        timestampKey: timestampKey,
      );
      return cached;
    }

    final fresh = await _fetchBreakFromApi(
      placement: placement,
      count: count,
      county: county,
      constituency: constituency,
      mediaHint: resolvedMediaHint,
    );
    if (fresh != null) {
      await _cacheBreakPayload(cacheKey, timestampKey, fresh);
      return fresh;
    }
    return _getStaleBreakPayload(cacheKey, timestampKey);
  }

  /// Get display configuration from server
  Future<AdDisplayConfig> getDisplayConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null) {
      return _cachedConfig!;
    }

    // Check local cache
    if (!forceRefresh) {
      final cached = _prefs.getString(_configCacheKey);
      if (cached != null) {
        try {
          _cachedConfig = AdDisplayConfig.fromJson(jsonDecode(cached));
          return _cachedConfig!;
        } catch (e) {
          // Invalid cache, continue to fetch
        }
      }
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/ads/public/config'))
          .timeout(_configRequestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cachedConfig = AdDisplayConfig.fromJson(data);
        await _prefs.setString(_configCacheKey, response.body);
        _markAdNetworkSuccess();
        return _cachedConfig!;
      }
    } catch (e) {
      // Return default config on error
      _markAdNetworkFailure();
    }

    return _cachedConfig ?? AdDisplayConfig();
  }

  /// Check if app launch ad should be shown (respects cooldown)
  Future<bool> shouldShowLaunchAd() async {
    final config = await getDisplayConfig();
    if (!config.launchAdEnabled) return false;

    final lastShown = _prefs.getInt(_lastLaunchAdKey);
    if (lastShown == null) return true;

    final lastShownTime = DateTime.fromMillisecondsSinceEpoch(lastShown);
    final cooldown = Duration(minutes: config.launchAdCooldownMinutes);

    return DateTime.now().difference(lastShownTime) > cooldown;
  }

  /// Mark launch ad as shown (updates cooldown timer)
  Future<void> markLaunchAdShown() async {
    await _prefs.setInt(
      _lastLaunchAdKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> markResumeAdShown() async {
    await _prefs.setInt(
      _lastResumeAdKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> markAppBackgrounded() async {
    await _prefs.setInt(
      _lastBackgroundAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> shouldShowResumeAd() async {
    final config = await getDisplayConfig();
    if (!config.launchAdResumeEnabled || !config.launchAdBreakEnabled) {
      return false;
    }

    final backgroundAt = _prefs.getInt(_lastBackgroundAtKey);
    if (backgroundAt == null) return false;

    final backgroundDuration = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(backgroundAt),
    );
    if (backgroundDuration.inSeconds < config.launchAdResumeMinBackgroundSeconds) {
      return false;
    }

    final lastResumeShown = _prefs.getInt(_lastResumeAdKey);
    if (lastResumeShown == null) return true;

    final lastShownTime = DateTime.fromMillisecondsSinceEpoch(lastResumeShown);
    final cooldown = Duration(minutes: config.launchAdResumeCooldownMinutes);
    return DateTime.now().difference(lastShownTime) >= cooldown;
  }

  /// Get app launch ad if available and cooldown passed
  Future<Advertisement?> getAppLaunchAd({
    String? county,
    String? constituency,
  }) async {
    if (!await shouldShowLaunchAd()) return null;

    return getTargetedAd(
      AdPlacement.APP_LAUNCH,
      county: county,
      constituency: constituency,
    );
  }

  Future<AdBreakPayload?> getAppLaunchBreak({
    String? county,
    String? constituency,
  }) async {
    if (!await shouldShowLaunchAd()) return null;
    final config = await getDisplayConfig();
    return getAdBreak(
      AdPlacement.APP_LAUNCH,
      count: config.launchAdBreakCount.clamp(1, 2),
      county: county,
      constituency: constituency,
    );
  }

  /// Get positions in rental feed where ads should appear
  Future<List<int>> getRentalFeedAdPositions() async {
    final config = await getDisplayConfig();
    return config.feedPositions;
  }

  /// Check if filter ad should be shown
  Future<bool> isFilterAdEnabled() async {
    final config = await getDisplayConfig();
    return config.filterAdEnabled;
  }

  /// Submit form data for a form-type ad
  Future<bool> submitForm(
    int adId,
    Map<String, dynamic> formData, {
    String? name,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/ads/$adId/form'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'formData': jsonEncode(formData),
              'submitterName': name,
              'submitterEmail': email,
              'submitterPhone': phone,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  String _resolveMediaHint() {
    final degraded = _consecutiveAdTimeouts >= 2 ||
        _lastAdRequestLatency > const Duration(milliseconds: 1800);
    return degraded ? 'LIGHT' : 'FULL';
  }

  void _markAdNetworkSuccess() {
    _consecutiveAdTimeouts = 0;
  }

  void _markAdNetworkFailure() {
    _consecutiveAdTimeouts = (_consecutiveAdTimeouts + 1).clamp(0, 8);
  }

  String _targetedCacheKey({
    required AdPlacement placement,
    String? county,
    String? constituency,
    required String mediaHint,
  }) {
    final countyKey = (county ?? '').trim().toLowerCase();
    final constituencyKey = (constituency ?? '').trim().toLowerCase();
    return '$_targetedCacheKeyPrefix${placement.name}_${countyKey}_${constituencyKey}_$mediaHint';
  }

  String _breakCacheKey({
    required AdPlacement placement,
    String? county,
    String? constituency,
    required String mediaHint,
    required int count,
  }) {
    final countyKey = (county ?? '').trim().toLowerCase();
    final constituencyKey = (constituency ?? '').trim().toLowerCase();
    return '$_breakCacheKeyPrefix${placement.name}_${count}_${countyKey}_${constituencyKey}_$mediaHint';
  }

  Future<Advertisement?> _fetchTargetedAdFromApi({
    required AdPlacement placement,
    String? county,
    String? constituency,
    required String mediaHint,
  }) async {
    final queryParams = {
      'placement': placement.name,
      if (county != null && county.isNotEmpty) 'county': county,
      if (constituency != null && constituency.isNotEmpty)
        'constituency': constituency,
      'mediaHint': mediaHint,
    };
    final uri = Uri.parse(
      '$_baseUrl/ads/public/targeted',
    ).replace(queryParameters: queryParams);

    final startedAt = DateTime.now();
    try {
      final response = await http.get(uri).timeout(_targetedRequestTimeout);
      _lastAdRequestLatency = DateTime.now().difference(startedAt);
      if (response.statusCode != 200) {
        _markAdNetworkFailure();
        return null;
      }
      final data = jsonDecode(response.body);
      if (data['available'] == true && data['ad'] != null) {
        _markAdNetworkSuccess();
        return Advertisement.fromJson(data['ad']);
      }
      _markAdNetworkSuccess();
      return null;
    } catch (_) {
      _markAdNetworkFailure();
      return null;
    }
  }

  void _refreshTargetedAdInBackground({
    required AdPlacement placement,
    String? county,
    String? constituency,
    required String mediaHint,
    required String cacheKey,
    required String timestampKey,
  }) {
    Future<void>(() async {
      final fresh = await _fetchTargetedAdFromApi(
        placement: placement,
        county: county,
        constituency: constituency,
        mediaHint: mediaHint,
      );
      if (fresh != null) {
        await _cacheTargetedAd(cacheKey, timestampKey, fresh);
      }
    });
  }

  Future<void> _cacheTargetedAd(
    String cacheKey,
    String timestampKey,
    Advertisement ad,
  ) async {
    await _prefs.setString(cacheKey, jsonEncode(ad.toJson()));
    await _prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<Advertisement?> _getCachedTargetedAd(
    String cacheKey,
    String timestampKey,
  ) async {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;
    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _targetedFreshExpiry) {
      return null;
    }
    final cached = _prefs.getString(cacheKey);
    if (cached == null || cached.isEmpty) return null;
    try {
      return Advertisement.fromJson(jsonDecode(cached));
    } catch (_) {
      return null;
    }
  }

  Advertisement? _getStaleTargetedAd(String cacheKey, String timestampKey) {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;
    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _targetedStaleAllowed) {
      return null;
    }
    final cached = _prefs.getString(cacheKey);
    if (cached == null || cached.isEmpty) return null;
    try {
      return Advertisement.fromJson(jsonDecode(cached));
    } catch (_) {
      return null;
    }
  }

  Future<AdBreakPayload?> _fetchBreakFromApi({
    required AdPlacement placement,
    required int count,
    String? county,
    String? constituency,
    required String mediaHint,
  }) async {
    final queryParams = {
      'placement': placement.name,
      'count': count.toString(),
      if (county != null && county.isNotEmpty) 'county': county,
      if (constituency != null && constituency.isNotEmpty)
        'constituency': constituency,
      'mediaHint': mediaHint,
    };
    final uri = Uri.parse(
      '$_baseUrl/ads/public/break',
    ).replace(queryParameters: queryParams);

    final startedAt = DateTime.now();
    try {
      final response = await http.get(uri).timeout(_breakRequestTimeout);
      _lastAdRequestLatency = DateTime.now().difference(startedAt);
      if (response.statusCode != 200) {
        _markAdNetworkFailure();
        return null;
      }
      _markAdNetworkSuccess();
      final data = jsonDecode(response.body);
      return AdBreakPayload.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      _markAdNetworkFailure();
      return null;
    }
  }

  void _refreshBreakInBackground({
    required AdPlacement placement,
    required int count,
    String? county,
    String? constituency,
    required String mediaHint,
    required String cacheKey,
    required String timestampKey,
  }) {
    Future<void>(() async {
      final payload = await _fetchBreakFromApi(
        placement: placement,
        count: count,
        county: county,
        constituency: constituency,
        mediaHint: mediaHint,
      );
      if (payload != null) {
        await _cacheBreakPayload(cacheKey, timestampKey, payload);
      }
    });
  }

  Future<void> _cacheBreakPayload(
    String cacheKey,
    String timestampKey,
    AdBreakPayload payload,
  ) async {
    await _prefs.setString(
      cacheKey,
      jsonEncode({
        'available': payload.available,
        'ads': payload.ads.map((a) => a.toJson()).toList(),
        'policy': {
          'skipMode': payload.policy.skipMode,
          'skipDelaySeconds': payload.policy.skipDelaySeconds,
        },
        'breakId': payload.breakId,
      }),
    );
    await _prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<AdBreakPayload?> _getCachedBreakPayload(
    String cacheKey,
    String timestampKey,
  ) async {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;
    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _breakFreshExpiry) {
      return null;
    }
    final cached = _prefs.getString(cacheKey);
    if (cached == null || cached.isEmpty) return null;
    try {
      return AdBreakPayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached)),
      );
    } catch (_) {
      return null;
    }
  }

  AdBreakPayload? _getStaleBreakPayload(String cacheKey, String timestampKey) {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;
    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _breakStaleAllowed) {
      return null;
    }
    final cached = _prefs.getString(cacheKey);
    if (cached == null || cached.isEmpty) return null;
    try {
      return AdBreakPayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached)),
      );
    } catch (_) {
      return null;
    }
  }

  // Cache helpers

  Future<List<Advertisement>?> _getCachedAds(
    String cacheKey,
    String timestampKey,
  ) async {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;

    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _cacheExpiry) return null;

    final cached = _prefs.getString(cacheKey);
    if (cached == null) return null;

    try {
      final list = jsonDecode(cached) as List;
      return list.map((json) => Advertisement.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  Future<List<Advertisement>?> _getStaleCache(
    String cacheKey,
    String timestampKey,
  ) async {
    final timestamp = _prefs.getInt(timestampKey);
    if (timestamp == null) return null;

    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _staleAllowed) return null;

    final cached = _prefs.getString(cacheKey);
    if (cached == null) return null;

    try {
      final list = jsonDecode(cached) as List;
      return list.map((json) => Advertisement.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheAds(
    String cacheKey,
    String timestampKey,
    List<Advertisement> ads,
  ) async {
    await _prefs.setString(
      cacheKey,
      jsonEncode(ads.map((a) => a.toJson()).toList()),
    );
    await _prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Clear all ad caches
  Future<void> clearCache() async {
    final keys = _prefs.getKeys().where(
      (k) =>
          k.startsWith(_cacheKeyPrefix) ||
          k.startsWith(_targetedCacheKeyPrefix) ||
          k.startsWith(_breakCacheKeyPrefix),
    );
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  /// Pre-fetch and cache ads for all placements (call on app start)
  Future<void> preloadAds() async {
    for (final placement in AdPlacement.values) {
      await getAdsForPlacement(placement, forceRefresh: true);
    }
  }
}
