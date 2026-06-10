import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/rentals/domain/rental_filters.dart';
import '../models/rental.dart';

class DeviceCachedRentals {
  final List<Rental> rentals;
  final bool isGeneral;

  const DeviceCachedRentals({required this.rentals, required this.isGeneral});
}

class DeviceRentalCacheService {
  DeviceRentalCacheService._();

  static const String _listKey = 'device_rentals_list_v1';
  static const String _detailsKey = 'device_rental_details_v1';
  static const Duration _listTtl = Duration(minutes: 10);
  static const Duration _detailTtl = Duration(minutes: 20);
  static const int _maxDetails = 20;

  static String signatureForFilters(RentalFilters filters) {
    final params = <String, dynamic>{
      ...filters.toRequestParams(),
      if (filters.unitType != null) 'unitType': filters.unitType!.backendName,
      if (filters.minPrice != null) 'minPrice': filters.minPrice,
      if (filters.maxPrice != null) 'maxPrice': filters.maxPrice,
      if (filters.bedrooms != null) 'bedrooms': filters.bedrooms,
    };
    return _stableEncode(params);
  }

  static Future<DeviceCachedRentals?> getCachedList(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
    final cachedSignature = decoded['signature']?.toString();
    if (cachedAt == null || cachedSignature != signature) {
      return null;
    }

    if (DateTime.now().difference(cachedAt) > _listTtl) {
      await prefs.remove(_listKey);
      return null;
    }

    final rentalsRaw = (decoded['rentals'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final rentals = rentalsRaw.map(Rental.fromJson).toList();
    final isGeneral = decoded['isGeneral'] == true;
    return DeviceCachedRentals(rentals: rentals, isGeneral: isGeneral);
  }

  static Future<void> setCachedList(
    String signature,
    List<Rental> rentals, {
    required bool isGeneral,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'cachedAt': DateTime.now().toIso8601String(),
      'signature': signature,
      'isGeneral': isGeneral,
      'rentals': rentals.map((r) => r.toJson()).toList(),
    };
    await prefs.setString(_listKey, jsonEncode(payload));
  }

  static Future<Rental?> getCachedDetail(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_detailsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entry = decoded['$id'] as Map<String, dynamic>?;
    if (entry == null) {
      return null;
    }

    final cachedAt = DateTime.tryParse(entry['cachedAt']?.toString() ?? '');
    if (cachedAt == null || DateTime.now().difference(cachedAt) > _detailTtl) {
      decoded.remove('$id');
      await prefs.setString(_detailsKey, jsonEncode(decoded));
      return null;
    }

    final data = entry['data'] as Map<String, dynamic>?;
    if (data == null) {
      return null;
    }

    return Rental.fromJson(data);
  }

  static Future<void> setCachedDetail(Rental rental) async {
    final id = rental.id;
    if (id == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_detailsKey);
    final decoded = raw != null && raw.isNotEmpty
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : <String, dynamic>{};

    decoded['$id'] = <String, dynamic>{
      'cachedAt': DateTime.now().toIso8601String(),
      'data': rental.toJson(),
    };

    _trimDetails(decoded);
    await prefs.setString(_detailsKey, jsonEncode(decoded));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_listKey);
    await prefs.remove(_detailsKey);
  }

  static void _trimDetails(Map<String, dynamic> entries) {
    if (entries.length <= _maxDetails) {
      return;
    }

    final sorted = entries.entries.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(
              (a.value as Map<String, dynamic>)['cachedAt']?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(
              (b.value as Map<String, dynamic>)['cachedAt']?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    for (final entry in sorted.skip(_maxDetails)) {
      entries.remove(entry.key);
    }
  }

  static String _stableEncode(Map<String, dynamic> values) {
    if (values.isEmpty) {
      return '{}';
    }
    final sortedKeys = values.keys.toList()..sort();
    final sorted = <String, dynamic>{};
    for (final key in sortedKeys) {
      sorted[key] = values[key];
    }
    return jsonEncode(sorted);
  }
}
