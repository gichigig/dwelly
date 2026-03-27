import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';

enum AlertType { AREA, VACANCY }

class RentalAlert {
  final int id;
  final AlertType alertType;
  final String? county;
  final String? constituency;
  final String? ward;
  final String? buildingName;
  final String? buildingAddress;
  final double? minPrice;
  final double? maxPrice;
  final int? minBedrooms;
  final int? maxBedrooms;
  final String? propertyType;
  final bool enabled;
  final bool pushNotification;
  final bool emailNotification;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;
  final int triggerCount;

  RentalAlert({
    required this.id,
    required this.alertType,
    this.county,
    this.constituency,
    this.ward,
    this.buildingName,
    this.buildingAddress,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.maxBedrooms,
    this.propertyType,
    required this.enabled,
    required this.pushNotification,
    required this.emailNotification,
    required this.createdAt,
    this.lastTriggeredAt,
    required this.triggerCount,
  });

  factory RentalAlert.fromJson(Map<String, dynamic> json) {
    return RentalAlert(
      id: json['id'],
      alertType: json['alertType'] == 'AREA'
          ? AlertType.AREA
          : AlertType.VACANCY,
      county: json['county'] ?? json['city'],
      constituency: json['constituency'],
      ward: json['ward'] ?? json['area'],
      buildingName: json['buildingName'],
      buildingAddress: json['buildingAddress'],
      minPrice: json['minPrice']?.toDouble(),
      maxPrice: json['maxPrice']?.toDouble(),
      minBedrooms: json['minBedrooms'],
      maxBedrooms: json['maxBedrooms'],
      propertyType: json['propertyType'],
      enabled: json['enabled'] ?? true,
      pushNotification: json['pushNotification'] ?? true,
      emailNotification: json['emailNotification'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      lastTriggeredAt: json['lastTriggeredAt'] != null
          ? DateTime.parse(json['lastTriggeredAt'])
          : null,
      triggerCount: json['triggerCount'] ?? 0,
    );
  }

  String get displayTitle {
    if (alertType == AlertType.AREA) {
      return ward ?? constituency ?? county ?? 'Any Area';
    } else {
      return buildingName ?? buildingAddress ?? 'Building Alert';
    }
  }

  String get displaySubtitle {
    List<String> parts = [];
    if (alertType == AlertType.AREA) {
      final locationBits = [
        ward,
        constituency,
        county,
      ].where((v) => v != null && v.trim().isNotEmpty).cast<String>().toList();
      if (locationBits.isNotEmpty) {
        parts.add(locationBits.join(', '));
      }
    }
    if (minBedrooms != null || maxBedrooms != null) {
      if (minBedrooms == maxBedrooms) {
        parts.add('$minBedrooms bed');
      } else if (minBedrooms != null && maxBedrooms != null) {
        parts.add('$minBedrooms-$maxBedrooms beds');
      } else if (minBedrooms != null) {
        parts.add('$minBedrooms+ beds');
      } else {
        parts.add('Up to $maxBedrooms beds');
      }
    }
    if (minPrice != null || maxPrice != null) {
      if (minPrice != null && maxPrice != null) {
        parts.add('KES ${minPrice!.toInt()}-${maxPrice!.toInt()}');
      } else if (minPrice != null) {
        parts.add('KES ${minPrice!.toInt()}+');
      } else {
        parts.add('Up to \$${maxPrice!.toInt()}');
      }
    }
    return parts.isEmpty ? 'All rentals' : parts.join(' • ');
  }
}

class CreateAlertRequest {
  final AlertType alertType;
  final String? county;
  final String? constituency;
  final String? ward;
  final String? buildingName;
  final String? buildingAddress;
  final double? minPrice;
  final double? maxPrice;
  final int? minBedrooms;
  final int? maxBedrooms;
  final String? propertyType;
  final bool pushNotification;
  final bool emailNotification;

  CreateAlertRequest({
    required this.alertType,
    this.county,
    this.constituency,
    this.ward,
    this.buildingName,
    this.buildingAddress,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.maxBedrooms,
    this.propertyType,
    this.pushNotification = true,
    this.emailNotification = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'alertType': alertType == AlertType.AREA ? 'AREA' : 'VACANCY',
      if (county != null) 'county': county,
      if (constituency != null) 'constituency': constituency,
      if (ward != null) 'ward': ward,
      if (buildingName != null) 'buildingName': buildingName,
      if (buildingAddress != null) 'buildingAddress': buildingAddress,
      if (minPrice != null) 'minPrice': minPrice,
      if (maxPrice != null) 'maxPrice': maxPrice,
      if (minBedrooms != null) 'minBedrooms': minBedrooms,
      if (maxBedrooms != null) 'maxBedrooms': maxBedrooms,
      if (propertyType != null) 'propertyType': propertyType,
      'pushNotification': pushNotification,
      'emailNotification': emailNotification,
    };
  }
}

class RentalAlertService {
  static Future<List<RentalAlert>> getAlerts() async {
    if (!AuthService.isLoggedIn) {
      // Return empty list if not logged in instead of throwing
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/rental-alerts'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => RentalAlert.fromJson(json)).toList();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Token expired or invalid - return empty list instead of throwing
        print('Auth error fetching alerts: ${response.statusCode}');
        return [];
      } else {
        print('Fetch alerts failed: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch alerts: ${response.statusCode}');
      }
    } catch (e) {
      print('Get alerts error: $e');
      // Return empty list on error to prevent UI crash
      return [];
    }
  }

  static Future<RentalAlert> createAlert(CreateAlertRequest request) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rental-alerts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        return RentalAlert.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to create alert');
      }
    } catch (e) {
      print('Create alert error: $e');
      rethrow;
    }
  }

  static Future<RentalAlert> updateAlert(
    int alertId,
    CreateAlertRequest request,
  ) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/rental-alerts/$alertId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        return RentalAlert.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to update alert');
      }
    } catch (e) {
      print('Update alert error: $e');
      rethrow;
    }
  }

  static Future<RentalAlert> toggleAlert(int alertId, bool enabled) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/rental-alerts/$alertId/toggle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'enabled': enabled}),
      );

      if (response.statusCode == 200) {
        return RentalAlert.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to toggle alert');
      }
    } catch (e) {
      print('Toggle alert error: $e');
      rethrow;
    }
  }

  static Future<bool> deleteAlert(int alertId) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/rental-alerts/$alertId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Delete alert error: $e');
      return false;
    }
  }

  static Future<int> getCount() async {
    if (!AuthService.isLoggedIn) {
      return 0;
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/rental-alerts/count'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Get alert count error: $e');
      return 0;
    }
  }
}
