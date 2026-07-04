import 'dart:convert';
import 'package:http/http.dart' as http;
import '../errors/app_error.dart';
import '../models/user.dart';
import '../models/helper_profile.dart';
import '../models/helper_review.dart';
import 'api_service.dart';
import 'auth_service.dart';

class HelperService {
  static Future<List<User>> getAvailableHelpers({String? county, String? category}) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/helper/available').replace(
        queryParameters: {
          if (county != null && county.isNotEmpty) 'county': county,
          if (category != null && category.isNotEmpty) 'category': category,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => User.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw AppError(
          code: AppErrorCode.unknown,
          message: 'Failed to load helpers',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error while fetching helpers',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<User> updateHelperProfile({
    required double price,
    required String coverageLevel,
    String? county,
    List<String>? constituencies,
    List<String>? wards,
    String? serviceCategory,
    double? serviceRadiusKm,
    String? serviceAreaMode,
    List<String>? offeredServices,
  }) async {
    try {
      final token = AuthService.token;
      if (token == null) {
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'You must be logged in to update helper profile.',
        );
      }

      final body = {
        'price': price,
        'coverageLevel': coverageLevel,
        if (county != null) 'county': county,
        if (constituencies != null && constituencies.isNotEmpty) 'constituencies': constituencies,
        if (wards != null && wards.isNotEmpty) 'wards': wards,
        if (serviceCategory != null) 'serviceCategory': serviceCategory,
        if (serviceRadiusKm != null) 'serviceRadiusKm': serviceRadiusKm,
        if (serviceAreaMode != null) 'serviceAreaMode': serviceAreaMode,
        if (offeredServices != null) 'offeredServices': offeredServices,
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helper/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        // Refresh the current user to get the latest helper data
        await AuthService.refreshCurrentUser();
        return AuthService.currentUser!;
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? 'Failed to update helper profile',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error while updating helper profile',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<HelperProfile> getHelperProfile(int helperId) async {
    try {
      final token = AuthService.token;
      final headers = <String, String>{};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/helpers/$helperId/profile'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return HelperProfile.fromJson(jsonDecode(response.body));
      } else {
        throw AppError(
          code: AppErrorCode.unknown,
          message: 'Failed to load helper profile',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error while fetching helper profile',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<List<HelperReview>> getHelperReviews(int helperId, {int page = 0, int size = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/helpers/$helperId/reviews?page=$page&size=$size'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> content = data['content'] ?? [];
        return content.map((json) => HelperReview.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw AppError(
          code: AppErrorCode.unknown,
          message: 'Failed to load reviews',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error while fetching reviews',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<HelperReview> submitReview({
    required int helperId,
    required int rating,
    required String comment,
  }) async {
    try {
      final token = AuthService.token;
      if (token == null) {
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'You must be logged in to leave a review.',
        );
      }

      final body = {
        'rating': rating,
        'comment': comment,
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helpers/$helperId/reviews'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return HelperReview.fromJson(jsonDecode(response.body));
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? data['message'] ?? 'Failed to submit review',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error while submitting review',
        technicalMessage: e.toString(),
      );
    }
  }
}
