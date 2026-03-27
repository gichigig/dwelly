import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/rental.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'cache_service.dart';

class SavedRental {
  final int id;
  final int rentalId;
  final Rental rental;
  final String? notes;
  final DateTime savedAt;

  SavedRental({
    required this.id,
    required this.rentalId,
    required this.rental,
    this.notes,
    required this.savedAt,
  });

  factory SavedRental.fromJson(Map<String, dynamic> json) {
    return SavedRental(
      id: json['id'],
      rentalId: json['rentalId'],
      rental: Rental.fromJson(json['rental']),
      notes: json['notes'],
      savedAt: DateTime.parse(json['savedAt']),
    );
  }
}

class PaginatedSavedRentals {
  final List<SavedRental> rentals;
  final bool hasMore;
  final int page;
  final int size;
  final int totalElements;

  PaginatedSavedRentals({
    required this.rentals,
    required this.hasMore,
    required this.page,
    required this.size,
    required this.totalElements,
  });
}

class SavedRentalService {
  static Future<PaginatedSavedRentals> getSavedRentalsPaginated({
    int page = 0,
    int size = 10,
    bool forceRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/saved-rentals?page=$page&size=$size'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map<String, dynamic>) {
          final content = (data['content'] as List<dynamic>? ?? []);
          final rentals = content
              .map((json) => SavedRental.fromJson(json as Map<String, dynamic>))
              .toList();

          final totalElements = (data['totalElements'] as num?)?.toInt() ?? 0;
          final isLast = data['last'] as bool? ?? true;
          final pageNumber = (data['number'] as num?)?.toInt() ?? page;
          final pageSize = (data['size'] as num?)?.toInt() ?? size;

          if (page == 0 && forceRefresh) {
            CacheManager.savedRentals.clear();
          }

          return PaginatedSavedRentals(
            rentals: rentals,
            hasMore: !isLast,
            page: pageNumber,
            size: pageSize,
            totalElements: totalElements,
          );
        }

        // Fallback for old non-paginated format.
        if (data is List) {
          final allRentals = data
              .map((json) => SavedRental.fromJson(json as Map<String, dynamic>))
              .toList();
          final start = page * size;
          if (start >= allRentals.length) {
            return PaginatedSavedRentals(
              rentals: const [],
              hasMore: false,
              page: page,
              size: size,
              totalElements: allRentals.length,
            );
          }
          final end = (start + size).clamp(0, allRentals.length);
          return PaginatedSavedRentals(
            rentals: allRentals.sublist(start, end),
            hasMore: end < allRentals.length,
            page: page,
            size: size,
            totalElements: allRentals.length,
          );
        }
      }

      throw Exception('Failed to fetch saved rentals');
    } catch (e) {
      print('Get paginated saved rentals error: $e');
      rethrow;
    }
  }

  static Future<List<SavedRental>> getSavedRentals({
    bool forceRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    // Return cached if available and not forcing refresh
    if (!forceRefresh) {
      final cached = CacheManager.savedRentals.value;
      if (cached != null) {
        return cached.cast<SavedRental>();
      }
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/all'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final results = data.map((json) => SavedRental.fromJson(json)).toList();
        CacheManager.savedRentals.set(results);
        return results;
      } else {
        throw Exception('Failed to fetch saved rentals');
      }
    } catch (e) {
      print('Get saved rentals error: $e');
      rethrow;
    }
  }

  static Future<List<int>> getSavedRentalIds({
    bool forceRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) {
      return [];
    }

    // Return cached if available
    if (!forceRefresh) {
      final cached = CacheManager.savedRentalIds.value;
      if (cached != null) {
        return cached.toList();
      }
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/ids'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final ids = data.map((id) => id as int).toList();
        CacheManager.savedRentalIds.set(ids.toSet());
        return ids;
      } else {
        return [];
      }
    } catch (e) {
      print('Get saved rental ids error: $e');
      return [];
    }
  }

  /// Check if a rental is saved — uses cached IDs if available, no network call needed.
  static Future<bool> isRentalSaved(int rentalId) async {
    if (!AuthService.isLoggedIn) {
      return false;
    }

    // Use cached IDs set if available (avoids separate API call)
    final cachedIds = CacheManager.savedRentalIds.value;
    if (cachedIds != null) {
      return cachedIds.contains(rentalId);
    }

    // Fallback: fetch IDs and check
    try {
      final ids = await getSavedRentalIds();
      return ids.contains(rentalId);
    } catch (e) {
      print('Check saved status error: $e');
      return false;
    }
  }

  static Future<bool> saveRental(int rentalId, {String? notes}) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/$rentalId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode(notes != null ? {'notes': notes} : {}),
      );

      if (response.statusCode == 200) {
        // Optimistically update cached IDs
        final cachedIds = CacheManager.savedRentalIds.value;
        if (cachedIds != null) {
          cachedIds.add(rentalId);
          CacheManager.savedRentalIds.set(cachedIds);
        }
        // Invalidate full list cache so it re-fetches
        CacheManager.savedRentals.clear();
        return true;
      }
      return false;
    } catch (e) {
      print('Save rental error: $e');
      return false;
    }
  }

  static Future<bool> unsaveRental(int rentalId) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/$rentalId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        // Optimistically update cached IDs
        final cachedIds = CacheManager.savedRentalIds.value;
        if (cachedIds != null) {
          cachedIds.remove(rentalId);
          CacheManager.savedRentalIds.set(cachedIds);
        }
        // Invalidate full list cache
        CacheManager.savedRentals.clear();
        return true;
      }
      return false;
    } catch (e) {
      print('Unsave rental error: $e');
      return false;
    }
  }

  static Future<bool> updateNotes(int rentalId, String notes) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/$rentalId/notes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'notes': notes}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Update notes error: $e');
      return false;
    }
  }

  static Future<int> getCount() async {
    if (!AuthService.isLoggedIn) {
      return 0;
    }

    // Use cached IDs if available
    final cachedIds = CacheManager.savedRentalIds.value;
    if (cachedIds != null) {
      return cachedIds.length;
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/saved-rentals/count'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Get saved count error: $e');
      return 0;
    }
  }
}
