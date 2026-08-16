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
  final String? areaName; // Popular area name/nickname
  final String? directions; // Directions to property
  // Legacy fields for backward compatibility
  final String city;
  final String state;
  final String zipCode;
  final int bedrooms;
  final int bathrooms;
  final int squareFeet;
  final int? floor;
  final String propertyType;
  final List<String> amenities;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final List<String> mediumUrls;
  final List<String> hashtags;
  final bool petsAllowed;
  final bool parkingAvailable;
  final String status;
  final String? availableFrom;
  final int? ownerId;
  final String? ownerName;
  final String? ownerEmail;
  final String? ownerPhone;
  final String? ownerAvatarUrl;
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

  // Video fields
  final bool hasVideo;
  final String? videoUrl;
  final String? compoundVideoUrl;
  final String? cardDisplayPreference;

  // Custom Audio fields
  final String? audioUrl;
  final String? audioTitle;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  // Media Text Overlay & Custom Fonts
  final String? overlayText;
  final String? overlayFont;
  final String? overlayColor;
  final String? overlayPosition;
  final String? overlayBgStyle;

  bool get hasOverlayText => overlayText != null && overlayText!.trim().isNotEmpty;

  // Sponsorship fields
  final String? sponsorshipType;
  final bool isSponsored;

  bool get hasAnyVideo =>
      hasVideo ||
      (videoUrl != null && videoUrl!.isNotEmpty) ||
      (compoundVideoUrl != null && compoundVideoUrl!.isNotEmpty);

  String? get effectiveVideoUrl => compoundVideoUrl ?? videoUrl;

  String? get displayMediaUrl {
    if (imageUrls.isNotEmpty && imageUrls.first.isNotEmpty) return imageUrls.first;
    if (thumbnailUrls.isNotEmpty && thumbnailUrls.first.isNotEmpty) return thumbnailUrls.first;
    if (mediumUrls.isNotEmpty && mediumUrls.first.isNotEmpty) return mediumUrls.first;
    if (effectiveVideoUrl != null && effectiveVideoUrl!.isNotEmpty) return effectiveVideoUrl;
    return null;
  }

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
    this.floor,
    required this.propertyType,
    this.amenities = const [],
    this.imageUrls = const [],
    this.thumbnailUrls = const [],
    this.mediumUrls = const [],
    this.hashtags = const [],
    this.petsAllowed = false,
    this.parkingAvailable = false,
    this.status = 'ACTIVE',
    this.availableFrom,
    this.ownerId,
    this.ownerName,
    this.ownerEmail,
    this.ownerPhone,
    this.ownerAvatarUrl,
    this.createdAt,
    this.updatedAt,
    this.ownerIsVerified = false,
    this.ownerUserType,
    this.ownerVerificationStatus,
    this.requiresApproval = false,
    this.approvalStatus,
    this.saveCount = 0,
    this.hasVideo = false,
    this.videoUrl,
    this.compoundVideoUrl,
    this.audioUrl,
    this.audioTitle,
    this.overlayText,
    this.overlayFont,
    this.overlayColor,
    this.overlayPosition,
    this.overlayBgStyle,
    this.cardDisplayPreference,
    this.sponsorshipType,
    this.isSponsored = false,
  });

  /// Returns true if the owner is a verified agent (gold badge)
  bool get isVerifiedAgent => ownerIsVerified && ownerUserType == 'AGENT';

  /// Returns true if the owner is a verified individual (blue badge)
  bool get isVerifiedIndividual =>
      ownerIsVerified &&
      (ownerUserType == 'INDIVIDUAL' || ownerUserType == null);

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
      floor: json['floor'],
      propertyType: json['propertyType'] ?? 'APARTMENT',
      amenities:
          (json['amenities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      imageUrls:
          (json['imageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      thumbnailUrls:
          (json['thumbnailUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      mediumUrls:
          (json['mediumUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      hashtags:
          (json['hashtags'] as List<dynamic>?)?.map((e) {
            final s = e.toString().trim();
            return s.startsWith('#') ? s : '#$s';
          }).toList() ??
          [],
      petsAllowed: json['petsAllowed'] ?? false,
      parkingAvailable: json['parkingAvailable'] ?? false,
      status: json['status'] ?? 'ACTIVE',
      availableFrom: json['availableFrom'],
      ownerId: json['ownerId'] ?? json['createdById'],
      ownerName: json['ownerName'] ?? json['createdByName'],
      ownerEmail: json['ownerEmail'],
      ownerPhone: json['ownerPhone'],
      ownerAvatarUrl: json['ownerAvatarUrl'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      ownerIsVerified: json['ownerIsVerified'] ?? false,
      ownerUserType: json['ownerUserType'],
      ownerVerificationStatus: json['ownerVerificationStatus'],
      requiresApproval: json['requiresApproval'] ?? false,
      approvalStatus: json['approvalStatus'],
      saveCount: json['saveCount'] ?? 0,
      hasVideo: json['hasVideo'] ?? false,
      videoUrl: json['videoUrl'],
      compoundVideoUrl: json['compoundVideoUrl'],
      audioUrl: json['audioUrl'],
      audioTitle: json['audioTitle'],
      overlayText: json['overlayText'],
      overlayFont: json['overlayFont'],
      overlayColor: json['overlayColor'],
      overlayPosition: json['overlayPosition'],
      overlayBgStyle: json['overlayBgStyle'],
      cardDisplayPreference: json['cardDisplayPreference'],
      sponsorshipType: json['sponsorshipType'],
      isSponsored: json['isSponsored'] ?? false,
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
      if (distanceMeters != null) 'distanceMeters': distanceMeters,
      if (areaName != null) 'areaName': areaName,
      if (directions != null) 'directions': directions,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'squareFeet': squareFeet,
      if (floor != null) 'floor': floor,
      'propertyType': propertyType,
      'amenities': amenities,
      'imageUrls': imageUrls,
      'thumbnailUrls': thumbnailUrls,
      'mediumUrls': mediumUrls,
      'hashtags': hashtags,
      'petsAllowed': petsAllowed,
      'parkingAvailable': parkingAvailable,
      'status': status,
      if (availableFrom != null) 'availableFrom': availableFrom,
      if (ownerId != null) 'ownerId': ownerId,
      if (ownerName != null) 'ownerName': ownerName,
      if (ownerEmail != null) 'ownerEmail': ownerEmail,
      if (ownerPhone != null) 'ownerPhone': ownerPhone,
      if (ownerAvatarUrl != null) 'ownerAvatarUrl': ownerAvatarUrl,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'ownerIsVerified': ownerIsVerified,
      if (ownerUserType != null) 'ownerUserType': ownerUserType,
      if (ownerVerificationStatus != null)
        'ownerVerificationStatus': ownerVerificationStatus,
      'requiresApproval': requiresApproval,
      if (approvalStatus != null) 'approvalStatus': approvalStatus,
      'saveCount': saveCount,
      'hasVideo': hasVideo,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (compoundVideoUrl != null) 'compoundVideoUrl': compoundVideoUrl,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (audioTitle != null) 'audioTitle': audioTitle,
      if (cardDisplayPreference != null)
        'cardDisplayPreference': cardDisplayPreference,
      if (sponsorshipType != null) 'sponsorshipType': sponsorshipType,
      'isSponsored': isSponsored,
    };
  }

  /// Get display location (prefer areaName, fallback to ward, then county)
  String get displayLocation {
    if (areaName != null && areaName!.trim().isNotEmpty) {
      return areaName!.trim();
    }
    if (ward != null && ward!.trim().isNotEmpty) {
      return ward!.trim();
    }
    if (constituency != null && constituency!.trim().isNotEmpty) {
      return constituency!.trim();
    }
    if (county != null && county!.trim().isNotEmpty) {
      return county!.trim();
    }
    // Fallback to old format
    if (city.trim().isNotEmpty) {
      final c = city.trim();
      final s = state.trim();
      if (s.isNotEmpty && s != c) {
        return '$c, $s';
      }
      return c;
    }
    final addr = address.trim();
    if (addr.isNotEmpty) return addr;
    return 'Kenya';
  }

  String get fullAddress {
    final parts = <String>[];
    if (address.trim().isNotEmpty) parts.add(address.trim());
    if (city.trim().isNotEmpty && !parts.contains(city.trim()))
      parts.add(city.trim());
    if (state.trim().isNotEmpty && !parts.contains(state.trim()))
      parts.add(state.trim());
    if (zipCode.trim().isNotEmpty && !parts.contains(zipCode.trim()))
      parts.add(zipCode.trim());
    if (parts.isEmpty) return displayLocation;
    return parts.join(', ');
  }

  /// Kenya-style full location string
  String get fullKenyaLocation {
    final parts = <String>[];
    if (areaName != null && areaName!.isNotEmpty) parts.add(areaName!);
    if (ward != null && ward!.isNotEmpty && ward != areaName) parts.add(ward!);
    if (constituency != null && constituency!.isNotEmpty)
      parts.add(constituency!);
    if (county != null && county!.isNotEmpty) parts.add('$county County');
    return parts.join(', ');
  }

  String get formattedPrice => 'KES ${price.toStringAsFixed(0)}/mo';
}
