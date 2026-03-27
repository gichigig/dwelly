import 'rental_filters.dart';

class RentalListing {
  final String id;
  final String title;
  final String description;
  final int price;
  final String location;
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
  final bool isFeatured;
  final bool isActive;

  const RentalListing({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.location,
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
    this.isFeatured = false,
    this.isActive = true,
  });

  RentalListing copyWith({
    String? id,
    String? title,
    String? description,
    int? price,
    String? location,
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
    bool? isFeatured,
    bool? isActive,
  }) {
    return RentalListing(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      location: location ?? this.location,
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
      isFeatured: isFeatured ?? this.isFeatured,
      isActive: isActive ?? this.isActive,
    );
  }
}
