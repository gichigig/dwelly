import 'dart:async';
import 'dart:convert';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';

class MpesaService {
  static const int _pollInterval = 3; // seconds
  static const int _maxPollAttempts = 40; // ~2 minutes

  /// Initiate STK Push for donation
  /// Returns a map with success status and response data
  static Future<MpesaStkResult> initiateSTKPush({
    required String phoneNumber,
    required int amount,
    String? accountReference,
    String? transactionDesc,
  }) async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}/mpesa/stk-push');
      
      // Format phone number to 254XXXXXXXXX
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      if (formattedPhone == null) {
        return MpesaStkResult.error('Invalid phone number format');
      }

      final response = await http.post(
        url,
        headers: ApiService.getHeaders(),
        body: jsonEncode({
          'phoneNumber': formattedPhone,
          'amount': amount,
          'accountReference': accountReference ?? 'DONATE',
          'transactionDesc': transactionDesc ?? 'Donation to Dwelly',
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        return MpesaStkResult.success(
          checkoutRequestId: data['checkoutRequestId'],
          merchantRequestId: data['merchantRequestId'],
          customerMessage: data['customerMessage'] ?? 'Please check your phone for the M-Pesa prompt',
        );
      } else {
        return MpesaStkResult.error(data['message'] ?? 'Failed to initiate payment');
      }
    } catch (e) {
      return MpesaStkResult.error('Network error. Please check your connection.');
    }
  }

  /// Poll for payment status
  static Future<MpesaStatusResult> checkStatus(String checkoutRequestId) async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}/mpesa/status/$checkoutRequestId');
      
      final response = await http.get(
        url,
        headers: ApiService.getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MpesaStatusResult(
          status: MpesaStatus.fromString(data['status']),
          amount: data['amount'],
          resultDesc: data['resultDesc'] ?? '',
          mpesaReceiptNumber: data['mpesaReceiptNumber'] ?? '',
        );
      } else if (response.statusCode == 404) {
        return MpesaStatusResult(status: MpesaStatus.pending);
      } else {
        return MpesaStatusResult(status: MpesaStatus.failed, resultDesc: 'Failed to check status');
      }
    } catch (e) {
      return MpesaStatusResult(status: MpesaStatus.failed, resultDesc: 'Network error');
    }
  }

  /// Initiate STK Push for premium purchase (KES 300)
  static Future<MpesaStkResult> initiatePremiumStkPush({
    required String phoneNumber,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      return MpesaStkResult.error('Please sign in to continue.');
    }

    try {
      final url = Uri.parse('${ApiService.baseUrl}/premium/stk-push');
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      if (formattedPhone == null) {
        return MpesaStkResult.error('Invalid phone number format');
      }

      final response = await http.post(
        url,
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode({'phoneNumber': formattedPhone}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return MpesaStkResult.success(
          checkoutRequestId: data['checkoutRequestId'],
          merchantRequestId: data['merchantRequestId'],
          customerMessage:
              data['customerMessage'] ?? 'Please check your phone for the M-Pesa prompt',
        );
      }
      return MpesaStkResult.error(data['message'] ?? 'Failed to initiate payment');
    } catch (e) {
      return MpesaStkResult.error('Network error. Please check your connection.');
    }
  }

  /// Check premium payment status
  static Future<PremiumStatusResult> checkPremiumStatus(String checkoutRequestId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      return PremiumStatusResult(status: MpesaStatus.failed, resultDesc: 'Please sign in to continue.');
    }

    try {
      final url = Uri.parse('${ApiService.baseUrl}/premium/status/$checkoutRequestId');
      final response = await http.get(
        url,
        headers: ApiService.getHeaders(token: AuthService.token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PremiumStatusResult(
          status: MpesaStatus.fromString(data['status'] ?? ''),
          amount: data['amount'],
          resultDesc: data['resultDesc'] ?? '',
          mpesaReceiptNumber: data['mpesaReceiptNumber'] ?? '',
          premiumActive: data['premiumActive'] == true,
          premiumExpiresAt: data['premiumExpiresAt'] != null
              ? DateTime.tryParse(data['premiumExpiresAt'].toString())
              : null,
        );
      } else if (response.statusCode == 404) {
        return PremiumStatusResult(status: MpesaStatus.pending);
      } else if (response.statusCode == 401) {
        return PremiumStatusResult(status: MpesaStatus.failed, resultDesc: 'Please sign in to continue.');
      }
      return PremiumStatusResult(status: MpesaStatus.failed, resultDesc: 'Failed to check status');
    } catch (e) {
      return PremiumStatusResult(status: MpesaStatus.failed, resultDesc: 'Network error');
    }
  }

  /// Wait for premium payment completion with polling
  static Stream<PremiumStatusResult> waitForPremiumPayment(String checkoutRequestId) async* {
    int attempts = 0;

    while (attempts < _maxPollAttempts) {
      await Future.delayed(const Duration(seconds: _pollInterval));

      final status = await checkPremiumStatus(checkoutRequestId);
      yield status;

      if (status.status != MpesaStatus.pending) {
        break;
      }

      attempts++;
    }

    if (attempts >= _maxPollAttempts) {
      yield PremiumStatusResult(
        status: MpesaStatus.failed,
        resultDesc: 'Payment timeout. Please check your M-Pesa messages.',
      );
    }
  }

  /// Wait for payment completion with polling
  static Stream<MpesaStatusResult> waitForPayment(String checkoutRequestId) async* {
    int attempts = 0;
    
    while (attempts < _maxPollAttempts) {
      await Future.delayed(const Duration(seconds: _pollInterval));
      
      final status = await checkStatus(checkoutRequestId);
      yield status;
      
      if (status.status != MpesaStatus.pending) {
        break;
      }
      
      attempts++;
    }
    
    // If we've exhausted attempts, yield a timeout status
    if (attempts >= _maxPollAttempts) {
      yield MpesaStatusResult(
        status: MpesaStatus.failed,
        resultDesc: 'Payment timeout. Please check your M-Pesa messages.',
      );
    }
  }

  /// Format phone number to 254XXXXXXXXX format
  static String? _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    
    // Handle different formats
    if (digits.startsWith('254') && digits.length == 12) {
      return digits;
    } else if (digits.startsWith('0') && digits.length == 10) {
      return '254${digits.substring(1)}';
    } else if (digits.startsWith('7') && digits.length == 9) {
      return '254$digits';
    } else if (digits.startsWith('1') && digits.length == 9) {
      return '254$digits';
    }
    
    return null;
  }

  /// Validate phone number format
  static bool isValidPhoneNumber(String phone) {
    return _formatPhoneNumber(phone) != null;
  }
}

/// Result of STK Push initiation
class MpesaStkResult {
  final bool success;
  final String? checkoutRequestId;
  final String? merchantRequestId;
  final String? customerMessage;
  final String? errorMessage;

  MpesaStkResult._({
    required this.success,
    this.checkoutRequestId,
    this.merchantRequestId,
    this.customerMessage,
    this.errorMessage,
  });

  factory MpesaStkResult.success({
    required String checkoutRequestId,
    required String merchantRequestId,
    required String customerMessage,
  }) {
    return MpesaStkResult._(
      success: true,
      checkoutRequestId: checkoutRequestId,
      merchantRequestId: merchantRequestId,
      customerMessage: customerMessage,
    );
  }

  factory MpesaStkResult.error(String message) {
    return MpesaStkResult._(
      success: false,
      errorMessage: message,
    );
  }
}

/// Payment status
enum MpesaStatus {
  pending,
  completed,
  failed,
  cancelled;

  static MpesaStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return MpesaStatus.completed;
      case 'FAILED':
        return MpesaStatus.failed;
      case 'CANCELLED':
        return MpesaStatus.cancelled;
      default:
        return MpesaStatus.pending;
    }
  }
}

/// Result of status check
class MpesaStatusResult {
  final MpesaStatus status;
  final int? amount;
  final String resultDesc;
  final String mpesaReceiptNumber;

  MpesaStatusResult({
    required this.status,
    this.amount,
    this.resultDesc = '',
    this.mpesaReceiptNumber = '',
  });
}

class PremiumStatusResult {
  final MpesaStatus status;
  final int? amount;
  final String resultDesc;
  final String mpesaReceiptNumber;
  final bool premiumActive;
  final DateTime? premiumExpiresAt;

  PremiumStatusResult({
    required this.status,
    this.amount,
    this.resultDesc = '',
    this.mpesaReceiptNumber = '',
    this.premiumActive = false,
    this.premiumExpiresAt,
  });
}
