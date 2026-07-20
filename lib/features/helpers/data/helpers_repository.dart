import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:dwelly/core/services/api_service.dart';
import 'package:dwelly/core/services/auth_service.dart';

class Helper {
  final int id;
  final String name;
  final double helperPrice;
  final String? helperCounty;
  final String? helperCoverageLevel;
  final List<String>? helperConstituencies;
  final List<String>? helperWards;
  final String? avatarUrl;

  Helper({
    required this.id,
    required this.name,
    required this.helperPrice,
    this.helperCounty,
    this.helperCoverageLevel,
    this.helperConstituencies,
    this.helperWards,
    this.avatarUrl,
  });

  factory Helper.fromJson(Map<String, dynamic> json) {
    return Helper(
      id: json['id'],
      name: json['name'],
      helperPrice: (json['helperPrice'] as num).toDouble(),
      helperCounty: json['helperCounty'],
      helperCoverageLevel: json['helperCoverageLevel'],
      helperConstituencies: json['helperConstituencies'] != null
          ? List<String>.from(json['helperConstituencies'])
          : null,
      helperWards: json['helperWards'] != null
          ? List<String>.from(json['helperWards'])
          : null,
      avatarUrl: json['avatarUrl'],
    );
  }
}

class HelpersRepository {
  HelpersRepository();

  Future<List<Helper>> getAvailableHelpers({String? county}) async {
    final token = AuthService.token;
    var uri = Uri.parse('${ApiService.baseUrl}/api/helper/available');
    if (county != null && county.isNotEmpty) {
      uri = uri.replace(queryParameters: {'county': county});
    }

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => Helper.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch helpers');
    }
  }

  Future<void> hireHelper(int helperId, String phone) async {
    final token = AuthService.token;
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/helper-jobs/hire/$helperId'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'phoneNumber': phone}),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to hire helper');
    }
  }
}

final helpersRepositoryProvider = Provider((ref) {
  return HelpersRepository();
});

final availableHelpersProvider = FutureProvider.family<List<Helper>, String?>((
  ref,
  county,
) {
  return ref
      .watch(helpersRepositoryProvider)
      .getAvailableHelpers(county: county);
});
