import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

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
