enum UnitType {
  bedsitter,
  singleRoom,
  doubleRoom,
  room,
  studio,
  airBnB,
  apartment,
  house,
  condo,
  townhouse,
  villa,
  penthouse,
  duplex,
  office,
  shop,
  warehouse,
  other,
}

class Listing {
  final String id;
  final String title;
  final String description;
  final String county;
  final String area;
  final int rentKsh;
  final UnitType unitType;
  final List<String> photos;
  final List<String> amenities;
  final String contactPhone;
  final String? contactWhatsApp;
  final String ownerId;
  final DateTime createdAt;
  final bool isTaken;
  final bool isFeatured;

  const Listing({
    required this.id,
    required this.title,
    required this.description,
    required this.county,
    required this.area,
    required this.rentKsh,
    required this.unitType,
    required this.photos,
    required this.amenities,
    required this.contactPhone,
    this.contactWhatsApp,
    required this.ownerId,
    required this.createdAt,
    this.isTaken = false,
    this.isFeatured = false,
  });

  Listing copyWith({
    String? id,
    String? title,
    String? description,
    String? county,
    String? area,
    int? rentKsh,
    UnitType? unitType,
    List<String>? photos,
    List<String>? amenities,
    String? contactPhone,
    String? contactWhatsApp,
    String? ownerId,
    DateTime? createdAt,
    bool? isTaken,
    bool? isFeatured,
  }) {
    return Listing(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      county: county ?? this.county,
      area: area ?? this.area,
      rentKsh: rentKsh ?? this.rentKsh,
      unitType: unitType ?? this.unitType,
      photos: photos ?? this.photos,
      amenities: amenities ?? this.amenities,
      contactPhone: contactPhone ?? this.contactPhone,
      contactWhatsApp: contactWhatsApp ?? this.contactWhatsApp,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      isTaken: isTaken ?? this.isTaken,
      isFeatured: isFeatured ?? this.isFeatured,
    );
  }
}
