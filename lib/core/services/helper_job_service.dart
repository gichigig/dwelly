import 'dart:convert';
import 'package:http/http.dart' as http;
import '../errors/app_error.dart';
import '../models/helper_job.dart';
import 'api_service.dart';
import 'auth_service.dart';

class HelperJobService {
  static Future<List<HelperJob>> getClientJobs({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final response = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/helper-jobs/client?page=$page&size=$size',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['content'] ?? [];
        return data
            .map((json) => HelperJob.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw AppError(
          code: AppErrorCode.unknown,
          message: 'Failed to load client jobs',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<List<HelperJob>> getHelperJobs({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final response = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/helper-jobs/helper?page=$page&size=$size',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['content'] ?? [];
        return data
            .map((json) => HelperJob.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw AppError(
          code: AppErrorCode.unknown,
          message: 'Failed to load helper jobs',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<void> hireHelper({
    required int helperId,
    required String phoneNumber,
  }) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final body = {'phoneNumber': phoneNumber};

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helper-jobs/hire/$helperId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return;
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? 'Failed to hire helper',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }

  /// Returns true if the current user already has an ACTIVE or PENDING_PAYMENT job with this helper.
  static Future<bool> hasActiveJobWithHelper(int helperId) async {
    try {
      final token = AuthService.token;
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/helper-jobs/status/$helperId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['hasActiveJob'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> approveJob(int jobId) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helper-jobs/$jobId/approve'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return;
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? 'Failed to approve job',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<void> disputeJob(int jobId) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helper-jobs/$jobId/dispute'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return;
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? 'Failed to dispute job',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }

  static Future<void> requestWithdrawal(double amount) async {
    try {
      final token = AuthService.token;
      if (token == null)
        throw const AppError(
          code: AppErrorCode.forbidden,
          message: 'Not logged in',
        );

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/helper/withdraw'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'amount': amount}),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        return;
      } else {
        final data = jsonDecode(response.body);
        throw AppError(
          code: AppErrorCode.unknown,
          message: data['error'] ?? 'Failed to request withdrawal',
          technicalMessage: response.body,
        );
      }
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.network(
        message: 'Network error',
        technicalMessage: e.toString(),
      );
    }
  }
}
