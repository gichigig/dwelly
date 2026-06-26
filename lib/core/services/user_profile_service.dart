import 'dart:convert';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../models/rental.dart';

class PublicProfile {
  final int id;
  final String firstName;
  final String lastName;
  final String? avatarUrl;
  final String role;
  final String? userType;
  final String? verificationStatus;
  final DateTime? memberSince;
  final List<Rental> activeListings;

  PublicProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.avatarUrl,
    required this.role,
    this.userType,
    this.verificationStatus,
    this.memberSince,
    required this.activeListings,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'] as Map<String, dynamic>? ?? {};
    final listingsJson = json['rentals'] as List<dynamic>? ?? [];
    return PublicProfile(
      id: profileJson['id'] as int? ?? 0,
      firstName: profileJson['firstName'] as String? ?? '',
      lastName: profileJson['lastName'] as String? ?? '',
      avatarUrl: profileJson['avatarUrl'] as String?,
      role: profileJson['role'] as String? ?? 'USER',
      userType: profileJson['userType'] as String?,
      verificationStatus: profileJson['verificationStatus'] as String?,
      memberSince: profileJson['createdAt'] != null ? DateTime.tryParse(profileJson['createdAt'].toString()) : null,
      activeListings: listingsJson.map((e) => Rental.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'avatarUrl': avatarUrl,
        'role': role,
        'userType': userType,
        'verificationStatus': verificationStatus,
        if (memberSince != null) 'createdAt': memberSince!.toIso8601String(),
      },
      'rentals': activeListings.map((e) => e.toJson()).toList(),
    };
  }
}

class UserProfileService {
  static Future<PublicProfile> getPublicProfile(int userId, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'public_profile_$userId';

    if (!forceRefresh) {
      final cachedStr = prefs.getString(cacheKey);
      if (cachedStr != null) {
        try {
          return PublicProfile.fromJson(jsonDecode(cachedStr));
        } catch (_) {
          // Fallback to fetching if cache is invalid
        }
      }
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/users/$userId/public-profile'),
      );

      if (response.statusCode == 200) {
        prefs.setString(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        return PublicProfile.fromJson(decoded);
      }
      
      throw ApiService.parseHttpError(response, fallbackMessage: 'Failed to load public profile.');
    } catch (e) {
      throw ApiService.parseException(e, fallbackMessage: 'Failed to load public profile.');
    }
  }
  
  static Future<void> clearProfileCache(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('public_profile_$userId');
  }
}
