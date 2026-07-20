import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/rental.dart';

class LandlordService {
  static Map<String, String> jsonHeadersWithAuth() {
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

  static Future<List<Rental>> getMyRentals() async {
    final response = await ApiService.timedGet(
      Uri.parse(
        '${ApiService.baseUrl}/rentals/user/${AuthService.currentUser?.id}/paginated?size=100',
      ),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(
        utf8.decode(response.bodyBytes),
      );
      final content = data['content'] as List<dynamic>? ?? [];
      return content.map((json) => Rental.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load rentals: ${response.statusCode}');
    }
  }

  static Future<List<dynamic>> getMyBuildings() async {
    final response = await ApiService.timedGet(
      Uri.parse('${ApiService.baseUrl}/buildings'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data;
    } else {
      throw Exception('Failed to load buildings: ${response.statusCode}');
    }
  }

  // More methods for buildings and rentals can be added here
}
