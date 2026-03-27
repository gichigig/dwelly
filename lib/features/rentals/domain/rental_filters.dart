enum UnitType {
  bedsitter, // Bedsitter - single room with kitchen/bathroom
  singleRoom, // Single room (shared facilities)
  doubleRoom, // Double room (shared facilities)
  room, // Generic room
  studio, // Studio apartment
  airBnB, // Air BnB
  apartment, // Apartment
  house, // House
  condo, // Condo
  townhouse, // Townhouse
  villa, // Villa
  penthouse, // Penthouse
  duplex, // Duplex
  office, // Office space
  shop, // Shop/retail
  warehouse, // Warehouse
  other, // Other
}

/// Human-readable labels for unit types
extension UnitTypeLabel on UnitType {
  String get label {
    switch (this) {
      case UnitType.bedsitter:
        return 'Bedsitter';
      case UnitType.singleRoom:
        return 'Single Room';
      case UnitType.doubleRoom:
        return 'Double Room';
      case UnitType.room:
        return 'Room';
      case UnitType.studio:
        return 'Studio';
      case UnitType.airBnB:
        return 'Air BnB';
      case UnitType.apartment:
        return 'Apartment';
      case UnitType.house:
        return 'House';
      case UnitType.condo:
        return 'Condo';
      case UnitType.townhouse:
        return 'Townhouse';
      case UnitType.villa:
        return 'Villa';
      case UnitType.penthouse:
        return 'Penthouse';
      case UnitType.duplex:
        return 'Duplex';
      case UnitType.office:
        return 'Office';
      case UnitType.shop:
        return 'Shop';
      case UnitType.warehouse:
        return 'Warehouse';
      case UnitType.other:
        return 'Other';
    }
  }

  String get shortLabel {
    switch (this) {
      case UnitType.bedsitter:
        return 'Bedsitter';
      case UnitType.singleRoom:
        return 'Single';
      case UnitType.doubleRoom:
        return 'Double';
      case UnitType.room:
        return 'Room';
      case UnitType.studio:
        return 'Studio';
      case UnitType.airBnB:
        return 'Air BnB';
      case UnitType.apartment:
        return 'Apt';
      case UnitType.house:
        return 'House';
      case UnitType.condo:
        return 'Condo';
      case UnitType.townhouse:
        return 'Town';
      case UnitType.villa:
        return 'Villa';
      case UnitType.penthouse:
        return 'Pent';
      case UnitType.duplex:
        return 'Duplex';
      case UnitType.office:
        return 'Office';
      case UnitType.shop:
        return 'Shop';
      case UnitType.warehouse:
        return 'Warehouse';
      case UnitType.other:
        return 'Other';
    }
  }

  /// Backend PropertyType enum name (SCREAMING_SNAKE_CASE)
  String get backendName {
    switch (this) {
      case UnitType.bedsitter:
        return 'BEDSITTER';
      case UnitType.singleRoom:
        return 'SINGLE_ROOM';
      case UnitType.doubleRoom:
        return 'DOUBLE_ROOM';
      case UnitType.room:
        return 'ROOM';
      case UnitType.studio:
        return 'STUDIO';
      case UnitType.airBnB:
        return 'AIR_BNB';
      case UnitType.apartment:
        return 'APARTMENT';
      case UnitType.house:
        return 'HOUSE';
      case UnitType.condo:
        return 'CONDO';
      case UnitType.townhouse:
        return 'TOWNHOUSE';
      case UnitType.villa:
        return 'VILLA';
      case UnitType.penthouse:
        return 'PENTHOUSE';
      case UnitType.duplex:
        return 'DUPLEX';
      case UnitType.office:
        return 'OFFICE';
      case UnitType.shop:
        return 'SHOP';
      case UnitType.warehouse:
        return 'WAREHOUSE';
      case UnitType.other:
        return 'OTHER';
    }
  }
}

class RentalFilters {
  final String? locationQuery;
  final String? nickname; // Area nickname for smart search
  final String? ward; // Direct ward search
  final String? constituency; // Constituency filter
  final String? county; // County filter
  final int? minPrice;
  final int? maxPrice;
  final UnitType? unitType;
  final int? bedrooms;
  final bool includeNearby; // Include neighboring wards in results
  final List<String>?
  fypTerms; // FYP (For You Page) search terms (wards + nicknames)

  const RentalFilters({
    this.locationQuery,
    this.nickname,
    this.ward,
    this.constituency,
    this.county,
    this.minPrice,
    this.maxPrice,
    this.unitType,
    this.bedrooms,
    this.includeNearby = true,
    this.fypTerms,
  });

  RentalFilters copyWith({
    String? locationQuery,
    String? nickname,
    String? ward,
    String? constituency,
    String? county,
    int? minPrice,
    int? maxPrice,
    UnitType? unitType,
    int? bedrooms,
    bool? includeNearby,
    List<String>? fypTerms,
  }) {
    return RentalFilters(
      locationQuery: locationQuery ?? this.locationQuery,
      nickname: nickname ?? this.nickname,
      ward: ward ?? this.ward,
      constituency: constituency ?? this.constituency,
      county: county ?? this.county,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      unitType: unitType ?? this.unitType,
      bedrooms: bedrooms ?? this.bedrooms,
      includeNearby: includeNearby ?? this.includeNearby,
      fypTerms: fypTerms ?? this.fypTerms,
    );
  }

  /// Create a cleared filter (reset all)
  RentalFilters clear() {
    return const RentalFilters();
  }

  /// Check if any location filter is applied
  bool get hasLocationFilter =>
      nickname != null ||
      ward != null ||
      constituency != null ||
      county != null ||
      (fypTerms != null && fypTerms!.isNotEmpty) ||
      (locationQuery != null && locationQuery!.isNotEmpty);

  /// Convert to request parameters for API
  Map<String, dynamic> toRequestParams() {
    return {
      if (nickname != null) 'nickname': nickname,
      if (ward != null) 'ward': ward,
      if (constituency != null) 'constituency': constituency,
      if (county != null) 'county': county,
      if (locationQuery != null) 'area': locationQuery,
      if (fypTerms != null && fypTerms!.isNotEmpty) 'fypTerms': fypTerms,
      if (minPrice != null) 'minPrice': minPrice,
      if (maxPrice != null) 'maxPrice': maxPrice,
      if (bedrooms != null) 'bedrooms': bedrooms,
      'includeNearby': includeNearby,
    };
  }

  @override
  String toString() =>
      'RentalFilters(location: $locationQuery, nickname: $nickname, ward: $ward, price: $minPrice-$maxPrice)';
}
