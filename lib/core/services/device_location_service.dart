import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Result from device location detection
class DeviceLocationResult {
  final double latitude;
  final double longitude;
  final String? ward;
  final String? constituency;
  final String? county;
  final String? areaName;
  final bool success;
  final String? errorMessage;

  DeviceLocationResult({
    required this.latitude,
    required this.longitude,
    this.ward,
    this.constituency,
    this.county,
    this.areaName,
    required this.success,
    this.errorMessage,
  });

  /// Check if we have valid location data
  bool get hasLocationData =>
      ward != null || constituency != null || county != null;

  /// Get the best available location name for display
  String get displayName {
    if (areaName != null && areaName!.isNotEmpty) return areaName!;
    if (ward != null && ward!.isNotEmpty) return ward!;
    if (constituency != null && constituency!.isNotEmpty) return constituency!;
    if (county != null && county!.isNotEmpty) return county!;
    return 'Unknown Location';
  }

  /// Get a detailed location string combining ward, constituency, county
  /// Format: "Ward, Constituency, County" or best available combination
  String get detailedDisplayName {
    final parts = <String>[];

    // Prioritize nickname/area name if available
    if (areaName != null && areaName!.isNotEmpty) {
      parts.add(areaName!);
    } else if (ward != null && ward!.isNotEmpty) {
      parts.add(ward!);
    }

    // Add constituency if different from ward
    if (constituency != null && constituency!.isNotEmpty) {
      final constName = constituency!;
      if (parts.isEmpty ||
          !parts.last.toLowerCase().contains(constName.toLowerCase())) {
        parts.add(constName);
      }
    }

    // Add county if not already included
    if (county != null && county!.isNotEmpty) {
      final countyName = county!;
      if (parts.isEmpty ||
          !parts.any(
            (p) => p.toLowerCase().contains(countyName.toLowerCase()),
          )) {
        parts.add(countyName);
      }
    }

    if (parts.isEmpty) return 'Unknown Location';
    return parts.join(', ');
  }

  factory DeviceLocationResult.error(String message) {
    return DeviceLocationResult(
      latitude: 0,
      longitude: 0,
      success: false,
      errorMessage: message,
    );
  }
}

/// Service to get device location and resolve it to Kenya administrative units
class DeviceLocationService {
  static const String _lastLocationKey = 'last_device_location';
  static const String _locationPermissionDeniedKey =
      'location_permission_denied';
  static const String _pendingProfileLocationKey = 'pending_profile_location';

  /// Check if user has previously denied location permission
  static Future<bool> hasUserDeniedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationPermissionDeniedKey) ?? false;
  }

  /// Set that user has denied location permission
  static Future<void> setUserDeniedLocation(bool denied) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationPermissionDeniedKey, denied);
  }

  /// Get cached last known location
  static Future<DeviceLocationResult?> getCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_lastLocationKey);
    if (cached != null) {
      try {
        final json = jsonDecode(cached);
        return DeviceLocationResult(
          latitude: json['latitude'] ?? 0,
          longitude: json['longitude'] ?? 0,
          ward: json['ward'],
          constituency: json['constituency'],
          county: json['county'],
          areaName: json['areaName'],
          success: true,
        );
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Cache location result
  static Future<void> _cacheLocation(DeviceLocationResult result) async {
    if (!result.success) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastLocationKey,
      jsonEncode({
        'latitude': result.latitude,
        'longitude': result.longitude,
        'ward': result.ward,
        'constituency': result.constituency,
        'county': result.county,
        'areaName': result.areaName,
      }),
    );
  }

  /// Check if location service is enabled on the device
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check current permission status (does NOT conflate service-off with denied)
  static Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission.
  /// Returns null if location service is disabled (caller should prompt user to enable it).
  static Future<LocationPermission?> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Try to open location settings so user can enable GPS
      await Geolocator.openLocationSettings();
      // Re-check after returning from settings
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Service still off — do NOT mark as user-denied
        return null;
      }
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // Only persist denial if user actively denied the permission prompt
    if (permission == LocationPermission.deniedForever) {
      await setUserDeniedLocation(true);
    } else if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await setUserDeniedLocation(false);
    }
    // Note: LocationPermission.denied (dismissed dialog) is NOT persisted
    // so the app will re-ask next time

    return permission;
  }

  /// Get current device location and resolve to ward
  static Future<DeviceLocationResult> getCurrentLocation() async {
    try {
      // First check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('[Location] Location service is disabled — opening settings');
        await Geolocator.openLocationSettings();
        // Re-check after user returns from settings
        final stillDisabled = !(await Geolocator.isLocationServiceEnabled());
        if (stillDisabled) {
          return DeviceLocationResult.error(
            'Location services are disabled. Please enable GPS in your device settings.',
          );
        }
      }

      // Check permission
      var permission = await Geolocator.checkPermission();
      print('[Location] Current permission: $permission');
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('[Location] After request, permission: $permission');
      }

      if (permission == LocationPermission.denied) {
        return DeviceLocationResult.error('Location permission denied');
      }

      if (permission == LocationPermission.deniedForever) {
        await setUserDeniedLocation(true);
        return DeviceLocationResult.error(
          'Location permission permanently denied. Please enable it in app settings.',
        );
      }

      // Permission granted — clear any stale denied flag
      await setUserDeniedLocation(false);

      // Strategy: try last known position first (instant), then fresh GPS
      Position? position;

      // Step 1: Try last known position (instant, no GPS needed)
      try {
        print('[Location] Trying getLastKnownPosition...');
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          print(
            '[Location] Got last known position: ${position.latitude}, ${position.longitude}',
          );
        } else {
          print('[Location] No last known position available');
        }
      } catch (e) {
        print('[Location] getLastKnownPosition error: $e');
      }

      // Step 2: If no last known position, get a fresh GPS fix
      if (position == null) {
        try {
          print(
            '[Location] Getting fresh GPS position (low accuracy first)...',
          );
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 15),
            ),
          );
          print(
            '[Location] Got low-accuracy position: ${position.latitude}, ${position.longitude}',
          );
        } catch (e) {
          print('[Location] Low-accuracy GPS failed: $e');
          // Try medium accuracy as fallback
          try {
            print('[Location] Retrying with medium accuracy...');
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 30),
              ),
            );
            print(
              '[Location] Got medium-accuracy position: ${position.latitude}, ${position.longitude}',
            );
          } catch (e2) {
            print('[Location] Medium-accuracy GPS also failed: $e2');
          }
        }
      }

      // If we still don't have a position, return cached or error
      if (position == null) {
        print('[Location] All GPS methods failed, trying cached location');
        final cached = await getCachedLocation();
        if (cached != null) {
          return cached;
        }
        return DeviceLocationResult.error(
          'Could not get GPS position. Make sure GPS is enabled and you are in an open area.',
        );
      }

      // Resolve to ward via backend
      print('[Location] Resolving coordinates to ward...');
      final wardResult = await _resolveCoordinatesToWard(
        position.latitude,
        position.longitude,
      );
      print('[Location] Ward result: $wardResult');
      if (wardResult['source'] != null) {
        print(
          '[Location] Resolve source=${wardResult['source']}, distanceMeters=${wardResult['distanceMeters']}',
        );
      }

      final result = DeviceLocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        ward: wardResult['ward'] as String?,
        constituency: wardResult['constituency'] as String?,
        county: wardResult['county'] as String?,
        areaName: wardResult['areaName'] as String?,
        success: true,
      );

      // Cache for future use
      await _cacheLocation(result);

      return result;
    } catch (e, stackTrace) {
      print('[Location] Error getting device location: $e');
      print('[Location] Stack trace: $stackTrace');

      // Try to return cached location
      final cached = await getCachedLocation();
      if (cached != null) {
        return cached;
      }

      return DeviceLocationResult.error('Failed to get location: $e');
    }
  }

  /// Resolve coordinates to ward using backend API
  static Future<Map<String, dynamic>> _resolveCoordinatesToWard(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/rentals/resolve-location')
          .replace(
            queryParameters: {
              'latitude': latitude.toString(),
              'longitude': longitude.toString(),
            },
          );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Only use backend result if it actually resolved to a location
        final ward = data['ward'] as String?;
        final constituency = data['constituency'] as String?;
        final county = data['county'] as String?;
        final areaName = data['areaName'] as String?;
        if (ward != null || constituency != null || county != null) {
          return {
            'ward': ward,
            'constituency': constituency,
            'county': county,
            'areaName': areaName,
            'source': data['source'],
            'distanceMeters': data['distanceMeters'],
          };
        }
        print(
          '[Location] Backend returned 200 but with empty data, falling back to local',
        );
      }
    } catch (e) {
      print('Error resolving coordinates: $e');
    }

    // Fallback: use local Kenya location data
    return _localResolveCoordinates(latitude, longitude);
  }

  /// Local fallback for resolving coordinates to Kenya administrative units
  static Map<String, dynamic> _localResolveCoordinates(
    double latitude,
    double longitude,
  ) {
    // Kenya ward boundaries (simplified - major areas)
    // This provides a basic fallback when backend is unavailable
    final kenyaWards = [
      // Minimal Kenya metro fallback; primary resolution is backend PostGIS.
      {
        'name': 'CBD',
        'ward': 'Nairobi Central',
        'constituency': 'Starehe',
        'county': 'Nairobi',
        'lat': -1.2864,
        'lng': 36.8172,
        'radius': 2.0,
      },
      {
        'name': 'Westlands',
        'ward': 'Parklands/Highridge',
        'constituency': 'Westlands',
        'county': 'Nairobi',
        'lat': -1.2636,
        'lng': 36.8030,
        'radius': 3.0,
      },
      {
        'name': 'Kilimani',
        'ward': 'Kilimani',
        'constituency': 'Dagoretti North',
        'county': 'Nairobi',
        'lat': -1.2884,
        'lng': 36.7833,
        'radius': 3.0,
      },
      {
        'name': 'Ruiru',
        'ward': 'Biashara Ward',
        'constituency': 'Ruiru',
        'county': 'Kiambu',
        'lat': -1.1500,
        'lng': 36.9600,
        'radius': 4.0,
      },
      {
        'name': 'Membley',
        'ward': 'Biashara Ward',
        'constituency': 'Ruiru',
        'county': 'Kiambu',
        'lat': -1.1650,
        'lng': 36.9550,
        'radius': 3.0,
      },
      {
        'name': 'Ruaka',
        'ward': 'Ndenderu',
        'constituency': 'Kiambaa',
        'county': 'Kiambu',
        'lat': -1.2094,
        'lng': 36.7778,
        'radius': 3.0,
      },
      {
        'name': 'Thika',
        'ward': 'Township',
        'constituency': 'Thika Town',
        'county': 'Kiambu',
        'lat': -1.0333,
        'lng': 37.0833,
        'radius': 5.0,
      },
      {
        'name': 'Sagana',
        'ward': 'Sagana',
        'constituency': 'Kirinyaga Central',
        'county': 'Kirinyaga',
        'lat': -0.6680,
        'lng': 37.2080,
        'radius': 20.0,
      },
      {
        'name': 'Kerugoya',
        'ward': 'Kerugoya',
        'constituency': 'Kirinyaga Central',
        'county': 'Kirinyaga',
        'lat': -0.4989,
        'lng': 37.2811,
        'radius': 15.0,
      },
      {
        'name': 'Nyeri',
        'ward': 'Rware',
        'constituency': 'Nyeri Town',
        'county': 'Nyeri',
        'lat': -0.4201,
        'lng': 36.9476,
        'radius': 15.0,
      },
      {
        'name': 'Embu',
        'ward': 'Majimbo',
        'constituency': 'Manyatta',
        'county': 'Embu',
        'lat': -0.5397,
        'lng': 37.4576,
        'radius': 20.0,
      },
      {
        'name': 'Meru',
        'ward': 'Township',
        'constituency': 'North Imenti',
        'county': 'Meru',
        'lat': 0.0463,
        'lng': 37.6559,
        'radius': 20.0,
      },
      {
        'name': 'Nanyuki',
        'ward': 'Municipality',
        'constituency': 'Laikipia East',
        'county': 'Laikipia',
        'lat': 0.0167,
        'lng': 37.0667,
        'radius': 20.0,
      },
      {
        'name': 'Nakuru',
        'ward': 'Nakuru East',
        'constituency': 'Nakuru Town East',
        'county': 'Nakuru',
        'lat': -0.3031,
        'lng': 36.0800,
        'radius': 12.0,
      },
      {
        'name': 'Nyali',
        'ward': 'Nyali',
        'constituency': 'Nyali',
        'county': 'Mombasa',
        'lat': -4.0200,
        'lng': 39.7100,
        'radius': 4.0,
      },
      {
        'name': 'Kisumu CBD',
        'ward': 'Kondele',
        'constituency': 'Kisumu Central',
        'county': 'Kisumu',
        'lat': -0.0917,
        'lng': 34.7680,
        'radius': 4.0,
      },
      {
        'name': 'Eldoret',
        'ward': 'Kapsoya',
        'constituency': 'Soy',
        'county': 'Uasin Gishu',
        'lat': 0.5143,
        'lng': 35.2698,
        'radius': 6.0,
      },
    ];

    // Find nearest ward within radius, and also track absolute nearest
    String? nearestInRadiusWard,
        nearestInRadiusConstituency,
        nearestInRadiusCounty,
        nearestInRadiusName;
    double minInRadiusDistance = double.infinity;
    String? nearestOverallWard,
        nearestOverallConstituency,
        nearestOverallCounty,
        nearestOverallName;
    double minOverallDistance = double.infinity;

    for (final ward in kenyaWards) {
      final distance = _calculateDistance(
        latitude,
        longitude,
        ward['lat'] as double,
        ward['lng'] as double,
      );

      // Track within radius
      final radius = ward['radius'] as double;
      if (distance <= radius && distance < minInRadiusDistance) {
        minInRadiusDistance = distance;
        nearestInRadiusWard = ward['ward'] as String;
        nearestInRadiusConstituency = ward['constituency'] as String;
        nearestInRadiusCounty = ward['county'] as String;
        nearestInRadiusName = ward['name'] as String;
      }

      // Track absolute nearest (fallback within 20km)
      if (distance < minOverallDistance) {
        minOverallDistance = distance;
        nearestOverallWard = ward['ward'] as String;
        nearestOverallConstituency = ward['constituency'] as String;
        nearestOverallCounty = ward['county'] as String;
        nearestOverallName = ward['name'] as String;
      }
    }

    // Prefer in-radius match, then a broader nearest fallback for non-metro areas.
    if (nearestInRadiusWard != null) {
      return {
        'ward': nearestInRadiusWard,
        'constituency': nearestInRadiusConstituency,
        'county': nearestInRadiusCounty,
        'areaName': nearestInRadiusName,
        'source': 'FALLBACK',
        'distanceMeters': minInRadiusDistance * 1000,
      };
    } else if (nearestOverallWard != null && minOverallDistance <= 80.0) {
      return {
        'ward': nearestOverallWard,
        'constituency': nearestOverallConstituency,
        'county': nearestOverallCounty,
        'areaName': nearestOverallName,
        'source': 'FALLBACK_APPROX',
        'distanceMeters': minOverallDistance * 1000,
      };
    }

    return {
      'ward': null,
      'constituency': null,
      'county': null,
      'areaName': null,
      'source': 'FALLBACK',
      'distanceMeters': null,
    };
  }

  /// Store location payload for profile sync after authentication.
  static Future<void> setPendingProfileLocation(DeviceLocationResult result) async {
    if (!result.success || !result.hasLocationData) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingProfileLocationKey,
      jsonEncode({
        'latitude': result.latitude,
        'longitude': result.longitude,
        'ward': result.ward,
        'constituency': result.constituency,
        'county': result.county,
        'areaName': result.areaName,
      }),
    );
  }

  static Future<Map<String, dynamic>?> getPendingProfileLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingProfileLocationKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearPendingProfileLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingProfileLocationKey);
  }

  /// Calculate distance between two coordinates (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
