import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Service for location-based search and nearby area recommendations
class LocationService {
  // Known areas with approximate coordinates (can be expanded)
  // This provides fallback when Google Maps API is not available
  static final Map<String, LatLng> _knownAreas = {
    'nairobi': LatLng(-1.2921, 36.8219),
    'westlands': LatLng(-1.2636, 36.8030),
    'kilimani': LatLng(-1.2884, 36.7833),
    'karen': LatLng(-1.3194, 36.7100),
    'lavington': LatLng(-1.2748, 36.7685),
    'kileleshwa': LatLng(-1.2758, 36.7816),
    'parklands': LatLng(-1.2595, 36.8196),
    'mombasa': LatLng(-4.0435, 39.6682),
    'kisumu': LatLng(-0.0917, 34.7680),
    'nakuru': LatLng(-0.3031, 36.0800),
    'eldoret': LatLng(0.5143, 35.2698),
    'thika': LatLng(-1.0334, 37.0693),
    'nyeri': LatLng(-0.4197, 36.9553),
    'malindi': LatLng(-3.2138, 40.1169),
    'langata': LatLng(-1.3547, 36.7578),
    'upperhill': LatLng(-1.2956, 36.8167),
    'runda': LatLng(-1.2167, 36.8333),
    'muthaiga': LatLng(-1.2500, 36.8333),
    'gigiri': LatLng(-1.2333, 36.8000),
    'spring valley': LatLng(-1.2500, 36.7667),
  };

  // Search radius in km for finding nearby areas
  static const double _searchRadiusKm = 30.0;
  
  /// Get coordinates for an area name
  static LatLng? getCoordinates(String area) {
    final normalized = area.toLowerCase().trim();
    return _knownAreas[normalized];
  }
  
  /// Find nearby areas based on a search term
  static List<String> getNearbyAreas(String searchArea, {double radiusKm = 30.0}) {
    final normalizedSearch = searchArea.toLowerCase().trim();
    final searchCoords = _knownAreas[normalizedSearch];
    
    if (searchCoords == null) {
      // If we don't know the area, return areas that contain the search term
      return _knownAreas.keys
          .where((area) => area.contains(normalizedSearch) || normalizedSearch.contains(area))
          .take(5)
          .toList();
    }
    
    // Find areas within radius
    final nearbyAreas = <MapEntry<String, double>>[];
    
    for (var entry in _knownAreas.entries) {
      if (entry.key == normalizedSearch) continue;
      
      final distance = _calculateDistance(
        searchCoords.lat, searchCoords.lng,
        entry.value.lat, entry.value.lng,
      );
      
      if (distance <= radiusKm) {
        nearbyAreas.add(MapEntry(entry.key, distance));
      }
    }
    
    // Sort by distance and return area names
    nearbyAreas.sort((a, b) => a.value.compareTo(b.value));
    return nearbyAreas.take(10).map((e) => e.key).toList();
  }
  
  /// Get all search terms for an area (the area + nearby areas)
  static List<String> getSearchTermsWithNearby(String area) {
    final terms = <String>[area];
    terms.addAll(getNearbyAreas(area));
    return terms;
  }
  
  /// Calculate distance between two coordinates using Haversine formula
  static double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  static double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }
  
  /// Format area name for display (capitalize)
  static String formatAreaName(String area) {
    return area.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
  
  /// Check if an area is known
  static bool isKnownArea(String area) {
    return _knownAreas.containsKey(area.toLowerCase().trim());
  }
  
  /// Get all known areas
  static List<String> getAllKnownAreas() {
    return _knownAreas.keys.map((a) => formatAreaName(a)).toList()..sort();
  }
}

class LatLng {
  final double lat;
  final double lng;
  
  const LatLng(this.lat, this.lng);
}
