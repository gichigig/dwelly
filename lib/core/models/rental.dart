class Rental {
  final int? id;
  final String title;
  final String description;
  final double price;
  final String address;
  // Kenya location fields
  final String? ward;
  final String? constituency;
  final String? county;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final String? areaName;      // Popular area name/nickname
  final String? directions;    // Directions to property
  // Legacy fields for backward compatibility
  final String city;
  final String state;
  final String zipCode;
  final int bedrooms;
  final int bathrooms;
  final int squareFeet;
  final String propertyType;
  final List<String> amenities;
  final List<String> imageUrls;
  final bool petsAllowed;
  final bool parkingAvailable;
  final String status;
  final String? availableFrom;
  final int? ownerId;
  final String? ownerName;
  final String? ownerEmail;
  final String? ownerPhone;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Owner verification info
  final bool ownerIsVerified;
  final String? ownerUserType;
  final String? ownerVerificationStatus;
  
  // Approval info
  final bool requiresApproval;
  final String? approvalStatus;

  // Popularity tracking
  final int saveCount;

  Rental({
    this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.address,
    this.ward,
    this.constituency,
    this.county,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.areaName,
    this.directions,
    this.city = '',
    this.state = '',
    this.zipCode = '',
    required this.bedrooms,
    required this.bathrooms,
    required this.squareFeet,
    required this.propertyType,
    this.amenities = const [],
    this.imageUrls = const [],
    this.petsAllowed = false,
    this.parkingAvailable = false,
    this.status = 'ACTIVE',
    this.availableFrom,
    this.ownerId,
    this.ownerName,
    this.ownerEmail,
    this.ownerPhone,
    this.createdAt,
    this.updatedAt,
    this.ownerIsVerified = false,
    this.ownerUserType,
    this.ownerVerificationStatus,
    this.requiresApproval = false,
    this.approvalStatus,
    this.saveCount = 0,
  });
  
  /// Returns true if the owner is a verified agent (gold badge)
  bool get isVerifiedAgent => ownerIsVerified && ownerUserType == 'AGENT';
  
  /// Returns true if the owner is a verified individual (blue badge)
  bool get isVerifiedIndividual => ownerIsVerified && (ownerUserType == 'INDIVIDUAL' || ownerUserType == null);

  factory Rental.fromJson(Map<String, dynamic> json) {
    return Rental(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      address: json['address'] ?? '',
      ward: json['ward'],
      constituency: json['constituency'],
      county: json['county'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      areaName: json['areaName'],
      directions: json['directions'],
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      zipCode: json['zipCode'] ?? '',
      bedrooms: json['bedrooms'] ?? 0,
      bathrooms: json['bathrooms'] ?? 0,
      squareFeet: json['squareFeet'] ?? 0,
      propertyType: json['propertyType'] ?? 'OTHER',
      amenities: (json['amenities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      imageUrls: (json['imageUrls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      petsAllowed: json['petsAllowed'] ?? false,
      parkingAvailable: json['parkingAvailable'] ?? false,
      status: json['status'] ?? 'ACTIVE',
      availableFrom: json['availableFrom'],
      ownerId: json['ownerId'] ?? json['createdById'],
      ownerName: json['ownerName'] ?? json['createdByName'],
      ownerEmail: json['ownerEmail'],
      ownerPhone: json['ownerPhone'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
      ownerIsVerified: json['ownerIsVerified'] ?? false,
      ownerUserType: json['ownerUserType'],
      ownerVerificationStatus: json['ownerVerificationStatus'],
      requiresApproval: json['requiresApproval'] ?? false,
      approvalStatus: json['approvalStatus'],
      saveCount: json['saveCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'price': price,
      'address': address,
      if (ward != null) 'ward': ward,
      if (constituency != null) 'constituency': constituency,
      if (county != null) 'county': county,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (areaName != null) 'areaName': areaName,
      if (directions != null) 'directions': directions,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'squareFeet': squareFeet,
      'propertyType': propertyType,
      'amenities': amenities,
      'imageUrls': imageUrls,
      'petsAllowed': petsAllowed,
      'parkingAvailable': parkingAvailable,
      'status': status,
      if (availableFrom != null) 'availableFrom': availableFrom,
    };
  }

  /// Get display location (prefer areaName, fallback to ward, then county)
  String get displayLocation {
    if (areaName != null && areaName!.isNotEmpty) {
      return areaName!;
    }
    if (ward != null && ward!.isNotEmpty) {
      return ward!;
    }
    if (constituency != null && constituency!.isNotEmpty) {
      return constituency!;
    }
    if (county != null && county!.isNotEmpty) {
      return county!;
    }
    // Fallback to old format
    if (city.isNotEmpty) {
      return '$city, $state';
    }
    return address;
  }

  String get fullAddress => '$address, $city, $state $zipCode';
  
  /// Kenya-style full location string
  String get fullKenyaLocation {
    final parts = <String>[];
    if (areaName != null && areaName!.isNotEmpty) parts.add(areaName!);
    if (ward != null && ward!.isNotEmpty && ward != areaName) parts.add(ward!);
    if (constituency != null && constituency!.isNotEmpty) parts.add(constituency!);
    if (county != null && county!.isNotEmpty) parts.add('$county County');
    return parts.join(', ');
  }
  
  String get formattedPrice => 'KES ${price.toStringAsFixed(0)}/mo';
}
