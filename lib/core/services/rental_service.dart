import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/kenya_locations.dart';
import '../models/rental.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'client_identity_service.dart';
import 'location_service.dart';
import 'auth_service.dart';

/// Response wrapper for paginated results
class PaginatedRentals {
  final List<Rental> rentals;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final bool hasMore;

  PaginatedRentals({
    required this.rentals,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.hasMore,
  });
}

/// Result from smart location search with resolved location info
class SmartLocationSearchResult {
  final PaginatedRentals rentals;
  final String? resolvedWard;
  final String? resolvedConstituency;
  final String? resolvedCounty;
  final String? anchorType;
  final String? anchorWard;
  final String? anchorConstituency;
  final String? anchorCounty;
  final double? anchorLatitude;
  final double? anchorLongitude;
  final List<String> nearbyAreas;
  final List<String> borderNeighborAreas;
  final List<String> expandedAreas;
  final List<RingBucket> ringBuckets;
  final String? searchSequence;
  final Map<String, int> tierCounts;
  final bool searchExhausted;
  final String? nextAction;
  final bool locationNotFound;
  final String? message;
  final String? searchedQuery;

  SmartLocationSearchResult({
    required this.rentals,
    this.resolvedWard,
    this.resolvedConstituency,
    this.resolvedCounty,
    this.anchorType,
    this.anchorWard,
    this.anchorConstituency,
    this.anchorCounty,
    this.anchorLatitude,
    this.anchorLongitude,
    this.nearbyAreas = const [],
    this.borderNeighborAreas = const [],
    this.expandedAreas = const [],
    this.ringBuckets = const [],
    this.searchSequence,
    this.tierCounts = const {},
    this.searchExhausted = false,
    this.nextAction,
    this.locationNotFound = false,
    this.message,
    this.searchedQuery,
  });

  /// Get display text for resolved location
  String get resolvedLocationDisplay {
    if (resolvedWard != null) return resolvedWard!;
    if (resolvedConstituency != null) return resolvedConstituency!;
    if (resolvedCounty != null) return resolvedCounty!;
    return searchedQuery ?? '';
  }

  bool get hasResults => rentals.rentals.isNotEmpty;
}

class RingBucket {
  final String label;
  final double minKm;
  final double maxKm;
  final int count;
  final int exactCoordinateCount;
  final int centroidFallbackCount;

  const RingBucket({
    required this.label,
    required this.minKm,
    required this.maxKm,
    required this.count,
    required this.exactCoordinateCount,
    required this.centroidFallbackCount,
  });

  factory RingBucket.fromJson(Map<String, dynamic> json) {
    return RingBucket(
      label: json['label']?.toString() ?? '',
      minKm: (json['minKm'] as num?)?.toDouble() ?? 0,
      maxKm: (json['maxKm'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      exactCoordinateCount:
          (json['exactCoordinateCount'] as num?)?.toInt() ?? 0,
      centroidFallbackCount:
          (json['centroidFallbackCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Search filters for rentals
class RentalFilters {
  final String? area;
  final String? constituency;
  final List<String>? nearbyAreas;
  final double? minPrice;
  final double? maxPrice;
  final int? bedrooms;
  final int? bathrooms;
  final String? propertyType;
  final List<int>? expandedBedrooms; // For FYP recommendations

  RentalFilters({
    this.area,
    this.constituency,
    this.nearbyAreas,
    this.minPrice,
    this.maxPrice,
    this.bedrooms,
    this.bathrooms,
    this.propertyType,
    this.expandedBedrooms,
  });

  RentalFilters copyWith({
    String? area,
    String? constituency,
    List<String>? nearbyAreas,
    double? minPrice,
    double? maxPrice,
    int? bedrooms,
    int? bathrooms,
    String? propertyType,
    List<int>? expandedBedrooms,
  }) {
    return RentalFilters(
      area: area ?? this.area,
      constituency: constituency ?? this.constituency,
      nearbyAreas: nearbyAreas ?? this.nearbyAreas,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      propertyType: propertyType ?? this.propertyType,
      expandedBedrooms: expandedBedrooms ?? this.expandedBedrooms,
    );
  }

  bool get hasFilters =>
      area != null ||
      constituency != null ||
      minPrice != null ||
      maxPrice != null ||
      bedrooms != null ||
      bathrooms != null ||
      propertyType != null;
}

class RentalService {
  static Map<String, String> _acceptHeadersWithAuth() {
    final headers = <String, String>{'Accept': 'application/json'};
    final token = AuthService.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Map<String, String> _jsonHeadersWithAuth() {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final token = AuthService.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static bool _containsIgnoreCase(String? value, String searchTerm) {
    if (value == null || value.isEmpty) return false;
    return value.toLowerCase().contains(searchTerm);
  }

  static bool _matchesAreaTerm(Rental rental, String searchTerm) {
    return _containsIgnoreCase(rental.areaName, searchTerm) ||
        _containsIgnoreCase(rental.ward, searchTerm) ||
        _containsIgnoreCase(rental.constituency, searchTerm) ||
        _containsIgnoreCase(rental.county, searchTerm) ||
        _containsIgnoreCase(rental.city, searchTerm) ||
        _containsIgnoreCase(rental.state, searchTerm) ||
        _containsIgnoreCase(rental.address, searchTerm);
  }

  static bool _isPubliclyVisibleRental(Rental rental) {
    final status = rental.status.toUpperCase();
    final approval = rental.approvalStatus?.toUpperCase();
    final isApproved = approval == null || approval == 'APPROVED';
    return status == 'ACTIVE' && isApproved;
  }

  static List<Rental> _filterPubliclyVisibleRentals(List<Rental> rentals) {
    return rentals.where(_isPubliclyVisibleRental).toList();
  }

  /// Get paginated rentals with optional filters
  static Future<PaginatedRentals> getPaginated({
    int page = 0,
    int size = 20,
    RentalFilters? filters,
    String sortBy = 'createdAt',
    String sortDirection = 'DESC',
  }) async {
    // Keep args for compatibility; backend paginated feed is newest-first.
    assert(sortBy.isNotEmpty);
    assert(sortDirection.isNotEmpty);
    try {
      return await _getPaginatedFromAll(
        page: page,
        size: size,
        filters: filters,
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load rentals.',
      );
      _logDebug('Error fetching paginated rentals', appError.technicalMessage);
      throw appError;
    }
  }

  /// Fallback method to get paginated results from all rentals
  static Future<PaginatedRentals> _getPaginatedFromAll({
    int page = 0,
    int size = 20,
    RentalFilters? filters,
  }) async {
    try {
      // Prefer backend endpoint that already returns active + approved rentals.
      final paginatedResponse = await ApiService.cachedGet(
        Uri.parse(
          '${ApiService.baseUrl}/rentals/paginated?page=$page&size=$size',
        ),
        headers: _acceptHeadersWithAuth(),
        ttl: page == 0
            ? const Duration(seconds: 45)
            : const Duration(seconds: 20),
        staleWhileRevalidate: page == 0
            ? const Duration(seconds: 120)
            : const Duration(seconds: 60),
      );

      if (paginatedResponse.statusCode == 200) {
        final data = jsonDecode(paginatedResponse.body) as Map<String, dynamic>;
        List<Rental> rentals = (data['rentals'] as List<dynamic>? ?? [])
            .map((json) => Rental.fromJson(json))
            .toList();
        rentals = _filterPubliclyVisibleRentals(rentals);

        if (filters != null) {
          rentals = _applyLocalFilters(rentals, filters);
        }

        return PaginatedRentals(
          rentals: rentals,
          totalElements: data['totalElements'] ?? rentals.length,
          totalPages: data['totalPages'] ?? 1,
          currentPage: data['currentPage'] ?? page,
          hasMore: data['hasMore'] ?? false,
        );
      }

      // Legacy fallback: this endpoint can include non-public statuses, so filter locally.
      final response = await ApiService.cachedGet(
        Uri.parse('${ApiService.baseUrl}/rentals'),
        headers: _acceptHeadersWithAuth(),
        ttl: const Duration(seconds: 30),
        staleWhileRevalidate: const Duration(seconds: 90),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Rental> allRentals;

        if (data is Map<String, dynamic> && data['content'] != null) {
          allRentals = (data['content'] as List)
              .map((json) => Rental.fromJson(json))
              .toList();
        } else if (data is List) {
          allRentals = data.map((json) => Rental.fromJson(json)).toList();
        } else {
          allRentals = [];
        }
        allRentals = _filterPubliclyVisibleRentals(allRentals);

        // Apply filters locally
        if (filters != null) {
          allRentals = _applyLocalFilters(allRentals, filters);
        }

        // Sort by creation date (newest first)
        allRentals.sort((a, b) {
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        });

        // Paginate
        final start = page * size;
        final end = (start + size).clamp(0, allRentals.length);
        final paginatedRentals = start < allRentals.length
            ? allRentals.sublist(start, end)
            : <Rental>[];

        return PaginatedRentals(
          rentals: paginatedRentals,
          totalElements: allRentals.length,
          totalPages: (allRentals.length / size).ceil(),
          currentPage: page,
          hasMore: end < allRentals.length,
        );
      } else {
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to load rentals.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load rentals.',
      );
      _logDebug('Error in fallback pagination', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  /// Search with nearby areas included
  static Future<PaginatedRentals> searchWithNearbyAreas({
    required String searchArea,
    int page = 0,
    int size = 20,
    RentalFilters? additionalFilters,
  }) async {
    try {
      // Get nearby areas
      final nearbyAreas = LocationService.getNearbyAreas(searchArea);
      final allAreas = [searchArea, ...nearbyAreas];

      // Fetch rentals for all areas and combine
      List<Rental> combinedRentals = [];

      for (var area in allAreas) {
        try {
          final result = await _getPaginatedFromAll(
            page: 0,
            size: 100, // Get more to combine
            filters: RentalFilters(area: area),
          );
          combinedRentals.addAll(result.rentals);
        } catch (e) {
          _logDebug('Error fetching area $area', e);
        }
      }

      // Remove duplicates by ID
      final seenIds = <int>{};
      combinedRentals = combinedRentals.where((r) {
        if (r.id == null || seenIds.contains(r.id)) return false;
        seenIds.add(r.id!);
        return true;
      }).toList();

      // Apply additional filters
      if (additionalFilters != null) {
        combinedRentals = _applyLocalFilters(
          combinedRentals,
          additionalFilters,
        );
      }

      // Sort: prioritize exact match, then by distance/relevance
      combinedRentals.sort((a, b) {
        final normalized = searchArea.toLowerCase();
        final aMatch = _matchesAreaTerm(a, normalized) ? 0 : 1;
        final bMatch = _matchesAreaTerm(b, normalized) ? 0 : 1;
        if (aMatch != bMatch) return aMatch.compareTo(bMatch);

        // Then by creation date
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });

      // Paginate
      final start = page * size;
      final end = (start + size).clamp(0, combinedRentals.length);
      final paginatedRentals = start < combinedRentals.length
          ? combinedRentals.sublist(start, end)
          : <Rental>[];

      return PaginatedRentals(
        rentals: paginatedRentals,
        totalElements: combinedRentals.length,
        totalPages: (combinedRentals.length / size).ceil(),
        currentPage: page,
        hasMore: end < combinedRentals.length,
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Search failed. Please try again.',
      );
      _logDebug('Error searching with nearby', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  /// Get FYP (For You Page) recommendations from backend
  /// Backend handles ward/neighbor ranking and save-count-aware ordering
  static Future<PaginatedRentals> getRecommendations({
    int page = 0,
    int size = 20,
    List<String>? preferredAreas,
    List<int>? expandedBedrooms,
    double? minPrice,
    double? maxPrice,
    String? ward,
    String? constituency,
    String? nickname,
  }) async {
    try {
      final clientId = await ClientIdentityService.getClientId();
      final requestBody = {
        'page': page,
        'size': size,
        'fypMode': true,
        'includeNearby': true,
        'clientId': clientId,
        if (preferredAreas != null && preferredAreas.isNotEmpty)
          'preferredAreas': preferredAreas,
        if (expandedBedrooms != null && expandedBedrooms.isNotEmpty)
          'expandedBedrooms': expandedBedrooms,
        if (minPrice != null) 'minPrice': minPrice,
        if (maxPrice != null) 'maxPrice': maxPrice,
        if (ward != null) 'ward': ward,
        if (constituency != null) 'constituency': constituency,
        if (nickname != null) 'nickname': nickname,
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rentals/recommendations'),
        headers: _jsonHeadersWithAuth(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List<dynamic> content = data['rentals'] ?? [];
        final rentals = _filterPubliclyVisibleRentals(
          content.map((json) => Rental.fromJson(json)).toList(),
        );

        return PaginatedRentals(
          rentals: rentals,
          totalElements: data['totalElements'] ?? rentals.length,
          totalPages: data['totalPages'] ?? 1,
          currentPage: data['currentPage'] ?? page,
          hasMore: data['hasMore'] ?? false,
        );
      }

      // Fallback to local recommendations
      return await _getLocalRecommendations(
        page: page,
        size: size,
        preferredAreas: preferredAreas,
        minPrice: minPrice,
        maxPrice: maxPrice,
      );
    } catch (e) {
      _logDebug('Error getting recommendations from backend', e);
      // Fallback to local recommendations
      return await _getLocalRecommendations(
        page: page,
        size: size,
        preferredAreas: preferredAreas,
        minPrice: minPrice,
        maxPrice: maxPrice,
      );
    }
  }

  static Future<void> recordRentalDetailOpen(
    int rentalId, {
    String source = 'EXPLORE',
  }) async {
    try {
      final clientId = await ClientIdentityService.getClientId();
      final token = AuthService.token;
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final deviceType = kIsWeb
          ? 'WEB'
          : (defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID');

      await http.post(
        Uri.parse('${ApiService.baseUrl}/rentals/$rentalId/interactions/click'),
        headers: headers,
        body: jsonEncode({
          'clientId': clientId,
          'source': source,
          'deviceType': deviceType,
        }),
      );
    } catch (e) {
      // Keep recommendations UX resilient when telemetry fails.
      _logDebug('Error recording rental detail click', e);
    }
  }

  /// Local fallback for FYP recommendations when backend is unavailable
  static Future<PaginatedRentals> _getLocalRecommendations({
    int page = 0,
    int size = 20,
    List<String>? preferredAreas,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final result = await _getPaginatedFromAll(page: 0, size: 500);
      var allRentals = result.rentals;

      // Score each rental based on area preference
      final scoredRentals = allRentals.map((rental) {
        double score = 0;

        if (preferredAreas != null && preferredAreas.isNotEmpty) {
          final rentalArea = '${rental.city}, ${rental.state}'.toLowerCase();
          final rentalWard = (rental.ward ?? '').toLowerCase();
          final rentalAreaName = (rental.areaName ?? '').toLowerCase();

          for (int i = 0; i < preferredAreas.length; i++) {
            final area = preferredAreas[i].toLowerCase();
            if (rentalArea.contains(area) ||
                rentalWard.contains(area) ||
                rentalAreaName.contains(area)) {
              score += (preferredAreas.length - i) * 10;
              break;
            }
          }
        }

        if (minPrice != null && maxPrice != null) {
          if (rental.price >= minPrice && rental.price <= maxPrice) {
            score += 20;
          }
        }

        if (rental.ownerIsVerified) {
          score += 5;
        }

        // Boost by save count
        score += rental.saveCount * 3;

        return MapEntry(rental, score);
      }).toList();

      scoredRentals.sort((a, b) {
        final scoreDiff = b.value.compareTo(a.value);
        if (scoreDiff != 0) return scoreDiff;

        if (a.key.createdAt == null && b.key.createdAt == null) return 0;
        if (a.key.createdAt == null) return 1;
        if (b.key.createdAt == null) return -1;
        return b.key.createdAt!.compareTo(a.key.createdAt!);
      });

      final sortedRentals = scoredRentals.map((e) => e.key).toList();

      final start = page * size;
      final end = (start + size).clamp(0, sortedRentals.length);
      final paginatedRentals = start < sortedRentals.length
          ? sortedRentals.sublist(start, end)
          : <Rental>[];

      return PaginatedRentals(
        rentals: paginatedRentals,
        totalElements: sortedRentals.length,
        totalPages: (sortedRentals.length / size).ceil(),
        currentPage: page,
        hasMore: end < sortedRentals.length,
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load recommendations.',
      );
      _logDebug('Error in local recommendations', appError.technicalMessage);
      throw appError;
    }
  }

  /// Apply filters locally to a list of rentals
  static List<Rental> _applyLocalFilters(
    List<Rental> rentals,
    RentalFilters filters,
  ) {
    return rentals.where((rental) {
      // Area filter (check Kenya location fields and legacy fields)
      if (filters.area != null && filters.area!.isNotEmpty) {
        final searchTerm = filters.area!.toLowerCase();
        final matchesArea = _matchesAreaTerm(rental, searchTerm);

        // Also check nearby areas if provided
        bool matchesNearby = false;
        if (filters.nearbyAreas != null) {
          matchesNearby = filters.nearbyAreas!.any(
            (area) => _matchesAreaTerm(rental, area.toLowerCase()),
          );
        }

        if (!matchesArea && !matchesNearby) return false;
      }

      if (filters.constituency != null && filters.constituency!.isNotEmpty) {
        final constituencyTerm = filters.constituency!.toLowerCase();
        if (!_containsIgnoreCase(rental.constituency, constituencyTerm)) {
          return false;
        }
      }

      // Price filters
      if (filters.minPrice != null && rental.price < filters.minPrice!) {
        return false;
      }
      if (filters.maxPrice != null && rental.price > filters.maxPrice!) {
        return false;
      }

      // Bedroom filter (exact or expanded)
      if (filters.bedrooms != null) {
        if (filters.expandedBedrooms != null &&
            filters.expandedBedrooms!.isNotEmpty) {
          if (!filters.expandedBedrooms!.contains(rental.bedrooms)) {
            return false;
          }
        } else if (rental.bedrooms != filters.bedrooms) {
          return false;
        }
      }

      // Bathroom filter
      if (filters.bathrooms != null && rental.bathrooms != filters.bathrooms) {
        return false;
      }

      // Property type filter
      if (filters.propertyType != null &&
          rental.propertyType.toLowerCase() !=
              filters.propertyType!.toLowerCase()) {
        return false;
      }

      return true;
    }).toList();
  }

  // Keep legacy methods for compatibility
  static Future<List<Rental>> getAll() async {
    final result = await getPaginated(page: 0, size: 100);
    return result.rentals;
  }

  /// Smart location search that calls backend with nickname/ward
  /// Returns rentals in tiered order: target ward, neighbors, then expanded nearby areas
  static Future<SmartLocationSearchResult> smartLocationSearch({
    String? nickname,
    String? ward,
    String? constituency,
    bool strictConstituency = false,
    String? county,
    double? latitude,
    double? longitude,
    bool sortByDistance = false,
    int page = 0,
    int size = 20,
    double? minPrice,
    double? maxPrice,
    int? bedrooms,
    String? propertyType,
    bool includeNearby = true,
  }) async {
    try {
      final requestBody = {
        if (nickname != null) 'nickname': nickname,
        if (ward != null) 'ward': ward,
        if (constituency != null) 'constituency': constituency,
        'strictConstituency': strictConstituency,
        if (county != null) 'area': county,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'sortByDistance': sortByDistance,
        'anchorMode': 'AUTO',
        if (minPrice != null) 'minPrice': minPrice,
        if (maxPrice != null) 'maxPrice': maxPrice,
        if (bedrooms != null) 'bedrooms': bedrooms,
        if (propertyType != null) 'propertyType': propertyType,
        'includeNearby': includeNearby,
        'page': page,
        'size': size,
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rentals/search/nearby'),
        headers: _jsonHeadersWithAuth(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List<dynamic> content = data['rentals'] ?? [];
        final rentals = _filterPubliclyVisibleRentals(
          content.map((json) => Rental.fromJson(json)).toList(),
        );

        return SmartLocationSearchResult(
          rentals: PaginatedRentals(
            rentals: rentals,
            totalElements: data['totalElements'] ?? rentals.length,
            totalPages: data['totalPages'] ?? 1,
            currentPage: data['currentPage'] ?? page,
            hasMore: data['hasMore'] ?? false,
          ),
          resolvedWard: data['resolvedWard'],
          resolvedConstituency: data['resolvedConstituency'],
          resolvedCounty: data['resolvedCounty'],
          anchorType: data['anchorType']?.toString(),
          anchorWard: data['anchorWard']?.toString(),
          anchorConstituency: data['anchorConstituency']?.toString(),
          anchorCounty: data['anchorCounty']?.toString(),
          anchorLatitude: (data['anchorLatitude'] as num?)?.toDouble(),
          anchorLongitude: (data['anchorLongitude'] as num?)?.toDouble(),
          nearbyAreas:
              (data['nearbyAreas'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
          borderNeighborAreas:
              (data['borderNeighborAreas'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
          expandedAreas:
              (data['expandedAreas'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
          ringBuckets:
              (data['ringBuckets'] as List<dynamic>?)
                  ?.map((e) {
                    if (e is Map<String, dynamic>) {
                      return RingBucket.fromJson(e);
                    }
                    if (e is Map) {
                      return RingBucket.fromJson(
                        e.map(
                          (key, value) =>
                              MapEntry(key.toString(), value),
                        ),
                      );
                    }
                    return null;
                  })
                  .whereType<RingBucket>()
                  .toList() ??
              const [],
          searchSequence: data['searchSequence']?.toString(),
          tierCounts:
              (data['tierCounts'] is Map<String, dynamic>)
                  ? (data['tierCounts'] as Map<String, dynamic>).map(
                      (key, value) => MapEntry(
                        key,
                        int.tryParse(value.toString()) ?? 0,
                      ),
                    )
                  : const {},
          searchExhausted: data['searchExhausted'] == true,
          nextAction: data['nextAction']?.toString(),
          locationNotFound: data['locationNotFound'] ?? false,
          message: data['message'],
          searchedQuery: data['searchedQuery'],
        );
      }

      // Fallback: location not found or error
      return SmartLocationSearchResult(
        rentals: PaginatedRentals(
          rentals: [],
          totalElements: 0,
          totalPages: 0,
          currentPage: page,
          hasMore: false,
        ),
        locationNotFound: true,
        message:
            'Unable to search. Try a different location or search by ward name.',
      );
    } catch (e) {
      _logDebug('Error in smart location search', e);

      // Return error result
      return SmartLocationSearchResult(
        rentals: PaginatedRentals(
          rentals: [],
          totalElements: 0,
          totalPages: 0,
          currentPage: page,
          hasMore: false,
        ),
        locationNotFound: true,
        message: 'Search failed. Please try again.',
      );
    }
  }

  static Future<Rental?> getById(int id, {bool forceRefresh = false}) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = CacheManager.rentalById.get('$id');
      if (cached != null) {
        return cached as Rental;
      }
    }

    try {
      final response = await ApiService.cachedGet(
        Uri.parse('${ApiService.baseUrl}/rentals/$id'),
        headers: const {'Accept': 'application/json'},
        ttl: const Duration(minutes: 3),
        staleWhileRevalidate: const Duration(minutes: 3),
      );

      if (response.statusCode == 200) {
        final rental = Rental.fromJson(jsonDecode(response.body));
        CacheManager.rentalById.set('$id', rental);
        return rental;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to load rental.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to load rental.',
      );
      _logDebug('Error fetching rental', appError.technicalMessage);
      throw appError;
    }
  }

  static Future<List<Rental>> search({
    String? city,
    String? propertyType,
    double? minPrice,
    double? maxPrice,
    int? bedrooms,
  }) async {
    final result = await getPaginated(
      page: 0,
      size: 100,
      filters: RentalFilters(
        area: city,
        propertyType: propertyType,
        minPrice: minPrice,
        maxPrice: maxPrice,
        bedrooms: bedrooms,
      ),
    );
    return result.rentals;
  }

  /// Fetch popular area names from backend (dynamic based on rental listings)
  /// Returns a list of popular area names with their listing counts
  static Future<List<PopularAreaResult>> getPopularAreas({
    String? query,
    int limit = 20,
  }) async {
    final cacheKey = '${query ?? 'all'}_$limit';

    // Check cache
    final cached = CacheManager.popularAreas.get(cacheKey);
    if (cached != null) {
      return cached.cast<PopularAreaResult>();
    }

    try {
      final params = <String, String>{'limit': limit.toString()};
      if (query != null && query.isNotEmpty) {
        params['query'] = query;
      }

      final uri = Uri.parse(
        '${ApiService.baseUrl}/rentals/popular-areas',
      ).replace(queryParameters: params);

      final response = await ApiService.cachedGet(
        uri,
        headers: const {'Accept': 'application/json'},
        ttl: const Duration(minutes: 30),
        staleWhileRevalidate: const Duration(minutes: 30),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final results = data
            .map((item) => PopularAreaResult.fromJson(item))
            .toList();
        CacheManager.popularAreas.set(cacheKey, results);
        return results;
      } else {
        _logDebug('Failed to fetch popular areas', response.statusCode);
        return [];
      }
    } catch (e) {
      _logDebug('Error fetching popular areas', e);
      return [];
    }
  }

  /// Search areas from backend (includes dynamic nicknames from listings + wards + constituencies)
  /// Returns LocationSearchResult objects that can be used directly in autocomplete
  static Future<List<LocationSearchResult>> searchAreas(String query) async {
    if (query.length < 2) return [];

    final cacheKey = query.toLowerCase().trim();

    // Check cache
    final cached = CacheManager.areaSearch.get(cacheKey);
    if (cached != null) {
      return cached.cast<LocationSearchResult>();
    }

    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/rentals/search-areas',
      ).replace(queryParameters: {'query': query});

      final response = await ApiService.cachedGet(
        uri,
        headers: const {'Accept': 'application/json'},
        ttl: const Duration(minutes: 10),
        staleWhileRevalidate: const Duration(minutes: 20),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final results = data.map((item) {
          final typeStr = item['type'] as String? ?? 'area';
          LocationType locType;
          switch (typeStr) {
            case 'county':
              locType = LocationType.county;
              break;
            case 'constituency':
              locType = LocationType.constituency;
              break;
            case 'ward':
              locType = LocationType.ward;
              break;
            default:
              locType = LocationType.area;
          }
          return LocationSearchResult(
            name: item['name'] ?? '',
            type: locType,
            ward: item['ward'],
            constituency: item['constituency'],
            county: item['county'],
            listingCount: item['listingCount'] ?? 0,
          );
        }).toList();
        CacheManager.areaSearch.set(cacheKey, results);
        return results;
      }
      return [];
    } catch (e) {
      _logDebug('Error searching areas', e);
      return [];
    }
  }

  static void _logDebug(String message, Object? details) {
    if (!kDebugMode) return;
    debugPrint('$message: $details');
  }
}

/// Result from popular areas API
class PopularAreaResult {
  final String name;
  final String? ward;
  final String? constituency;
  final String? county;
  final int listingCount;

  PopularAreaResult({
    required this.name,
    this.ward,
    this.constituency,
    this.county,
    required this.listingCount,
  });

  factory PopularAreaResult.fromJson(Map<String, dynamic> json) {
    return PopularAreaResult(
      name: json['name'] ?? '',
      ward: json['ward'],
      constituency: json['constituency'],
      county: json['county'],
      listingCount: json['listingCount'] ?? 0,
    );
  }
}
