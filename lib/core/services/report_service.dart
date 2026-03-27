import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'auth_service.dart';

class ReportReason {
  final String value;
  final String label;

  ReportReason({required this.value, required this.label});

  factory ReportReason.fromJson(Map<String, dynamic> json) {
    return ReportReason(value: json['value'] ?? '', label: json['label'] ?? '');
  }

  static List<ReportReason> defaultReasons = [
    ReportReason(value: 'SCAM', label: 'Scam or Fraud'),
    ReportReason(value: 'MISLEADING', label: 'Misleading Information'),
    ReportReason(value: 'INAPPROPRIATE', label: 'Inappropriate Content'),
    ReportReason(value: 'DUPLICATE', label: 'Duplicate Listing'),
    ReportReason(value: 'UNAVAILABLE', label: 'Property No Longer Available'),
    ReportReason(value: 'FAKE_PHOTOS', label: 'Fake Photos'),
    ReportReason(value: 'WRONG_PRICE', label: 'Incorrect Price'),
    ReportReason(value: 'HARASSMENT', label: 'Harassment'),
    ReportReason(value: 'OTHER', label: 'Other'),
  ];
}

class Report {
  final int id;
  final int reporterId;
  final String? reporterName;
  final String? reporterEmail;
  final int rentalId;
  final String? rentalTitle;
  final int? reportedUserId;
  final String? reportedUserName;
  final String? reportedUserEmail;
  final String reason;
  final String reasonDisplayName;
  final String description;
  final String status;
  final int? reviewedById;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? adminNotes;
  final String? actionTaken;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Report({
    required this.id,
    required this.reporterId,
    this.reporterName,
    this.reporterEmail,
    required this.rentalId,
    this.rentalTitle,
    this.reportedUserId,
    this.reportedUserName,
    this.reportedUserEmail,
    required this.reason,
    required this.reasonDisplayName,
    required this.description,
    required this.status,
    this.reviewedById,
    this.reviewedByName,
    this.reviewedAt,
    this.adminNotes,
    this.actionTaken,
    this.createdAt,
    this.updatedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] ?? 0,
      reporterId: json['reporterId'] ?? 0,
      reporterName: json['reporterName'],
      reporterEmail: json['reporterEmail'],
      rentalId: json['rentalId'] ?? 0,
      rentalTitle: json['rentalTitle'],
      reportedUserId: json['reportedUserId'],
      reportedUserName: json['reportedUserName'],
      reportedUserEmail: json['reportedUserEmail'],
      reason: json['reason'] ?? '',
      reasonDisplayName: json['reasonDisplayName'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'PENDING',
      reviewedById: json['reviewedById'],
      reviewedByName: json['reviewedByName'],
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.tryParse(json['reviewedAt'].toString())
          : null,
      adminNotes: json['adminNotes'],
      actionTaken: json['actionTaken'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return 'Pending';
      case 'UNDER_REVIEW':
        return 'Under Review';
      case 'RESOLVED':
        return 'Resolved';
      case 'DISMISSED':
        return 'Dismissed';
      default:
        return status;
    }
  }
}

class ReportService {
  static String get baseUrl => ApiService.baseUrl;

  static Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    // Reports API is JWT-authenticated.
    if (AuthService.isLoggedIn && AuthService.token != null) {
      headers['Authorization'] = 'Bearer ${AuthService.token}';
    }
    return headers;
  }

  /// Create a new report
  static Future<Report?> createReport({
    required int rentalId,
    required String reason,
    required String description,
  }) async {
    try {
      final response = await ApiService.timedPost(
        Uri.parse('$baseUrl/reports'),
        headers: _headers,
        body: jsonEncode({
          'rentalId': rentalId,
          'reason': reason,
          'description': description,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Report.fromJson(data);
      } else {
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Please sign in to submit reports.');
        }
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to submit report');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating report: $e');
      }
      rethrow;
    }
  }

  /// Check if user has already reported a rental
  static Future<bool> hasReportedRental(int rentalId) async {
    try {
      final response = await ApiService.timedGet(
        Uri.parse('$baseUrl/reports/check/$rentalId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['hasReported'] ?? false;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return false;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking report status: $e');
      }
      return false;
    }
  }

  /// Get report reasons
  static Future<List<ReportReason>> getReportReasons() async {
    try {
      final response = await ApiService.timedGet(
        Uri.parse('$baseUrl/reports/reasons'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => ReportReason.fromJson(e)).toList();
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return ReportReason.defaultReasons;
      }
      return ReportReason.defaultReasons;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching report reasons: $e');
      }
      return ReportReason.defaultReasons;
    }
  }

  /// Get my submitted reports
  static Future<List<Report>> getMyReports({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await ApiService.timedGet(
        Uri.parse('$baseUrl/reports/my-reports?page=$page&size=$size'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> content = data['content'] ?? [];
        return content.map((e) => Report.fromJson(e)).toList();
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return [];
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching my reports: $e');
      }
      return [];
    }
  }
}
