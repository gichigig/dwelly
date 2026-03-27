class MarketplaceProduct {
  final int? id;
  final String title;
  final String description;
  final double price;
  final double? originalPrice;
  final int discountPercent;
  final int stockQuantity;
  final bool inStock;
  final String deliveryType;
  final double deliveryFee;
  final String? estimatedDeliveryText;
  final String category;
  final String condition;
  final String county;
  final String constituency;
  final String ward;
  final double? latitude;
  final double? longitude;
  final List<String> imageUrls;
  final String? contactPhone;
  final bool showPhone;
  final String status;
  final String moderationStatus;
  final int? createdById;
  final String? sellerName;
  final bool sellerVerified;
  final DateTime? sellerJoinedAt;
  final int viewCount;
  final int chatClickCount;
  final int saveCount;
  final int likeCount;
  final double averageRating;
  final int ratingCount;
  final bool savedByViewer;
  final bool likedByViewer;
  final bool sponsored;
  final String sponsorshipStatus;
  final DateTime? sponsoredFrom;
  final DateTime? sponsoredUntil;
  final int? sponsorshipMultiplier;
  final String visibilityScope;
  final String? targetCounty;
  final bool sellerMarketplaceBadge;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MarketplaceProduct({
    this.id,
    required this.title,
    required this.description,
    required this.price,
    this.originalPrice,
    this.discountPercent = 0,
    this.stockQuantity = 0,
    this.inStock = true,
    this.deliveryType = 'BOTH',
    this.deliveryFee = 0,
    this.estimatedDeliveryText,
    required this.category,
    required this.condition,
    required this.county,
    required this.constituency,
    required this.ward,
    this.latitude,
    this.longitude,
    this.imageUrls = const [],
    this.contactPhone,
    this.showPhone = false,
    this.status = 'ACTIVE',
    this.moderationStatus = 'VISIBLE',
    this.createdById,
    this.sellerName,
    this.sellerVerified = false,
    this.sellerJoinedAt,
    this.viewCount = 0,
    this.chatClickCount = 0,
    this.saveCount = 0,
    this.likeCount = 0,
    this.averageRating = 0,
    this.ratingCount = 0,
    this.savedByViewer = false,
    this.likedByViewer = false,
    this.sponsored = false,
    this.sponsorshipStatus = 'NONE',
    this.sponsoredFrom,
    this.sponsoredUntil,
    this.sponsorshipMultiplier,
    this.visibilityScope = 'PUBLIC',
    this.targetCounty,
    this.sellerMarketplaceBadge = false,
    this.createdAt,
    this.updatedAt,
  });

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    final parsedStock = (json['stockQuantity'] as num?)?.toInt() ?? 0;
    final hasInStockFlag =
        json.containsKey('isInStock') || json.containsKey('inStock');
    final parsedInStock = hasInStockFlag
        ? (json['isInStock'] == true || json['inStock'] == true)
        : parsedStock > 0;
    return MarketplaceProduct(
      id: json['id'] as int?,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
      stockQuantity: parsedStock,
      inStock: parsedInStock,
      deliveryType: (json['deliveryType'] ?? 'BOTH') as String,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      estimatedDeliveryText: json['estimatedDeliveryText'] as String?,
      category: (json['category'] ?? 'OTHER') as String,
      condition: (json['condition'] ?? 'USED_GOOD') as String,
      county: (json['county'] ?? '') as String,
      constituency: (json['constituency'] ?? '') as String,
      ward: (json['ward'] ?? '') as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imageUrls:
          (json['imageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      contactPhone: json['contactPhone'] as String?,
      showPhone: json['showPhone'] == true,
      status: (json['status'] ?? 'ACTIVE') as String,
      moderationStatus: (json['moderationStatus'] ?? 'VISIBLE') as String,
      createdById: json['createdById'] as int?,
      sellerName: json['sellerName'] as String?,
      sellerVerified: json['sellerVerified'] == true,
      sellerJoinedAt: json['sellerJoinedAt'] != null
          ? DateTime.tryParse(json['sellerJoinedAt'])
          : null,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      chatClickCount: (json['chatClickCount'] as num?)?.toInt() ?? 0,
      saveCount: (json['saveCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      savedByViewer: json['savedByViewer'] == true,
      likedByViewer: json['likedByViewer'] == true,
      sponsored: json['sponsored'] == true,
      sponsorshipStatus: (json['sponsorshipStatus'] ?? 'NONE') as String,
      sponsoredFrom: json['sponsoredFrom'] != null
          ? DateTime.tryParse(json['sponsoredFrom'])
          : null,
      sponsoredUntil: json['sponsoredUntil'] != null
          ? DateTime.tryParse(json['sponsoredUntil'])
          : null,
      sponsorshipMultiplier: (json['sponsorshipMultiplier'] as num?)?.toInt(),
      visibilityScope: (json['visibilityScope'] ?? 'PUBLIC') as String,
      targetCounty: json['targetCounty'] as String?,
      sellerMarketplaceBadge: json['sellerMarketplaceBadge'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'price': price,
      if (originalPrice != null) 'originalPrice': originalPrice,
      'discountPercent': discountPercent,
      'stockQuantity': stockQuantity,
      'deliveryType': deliveryType,
      'deliveryFee': deliveryFee,
      if (estimatedDeliveryText != null)
        'estimatedDeliveryText': estimatedDeliveryText,
      'category': category,
      'condition': condition,
      'county': county,
      'constituency': constituency,
      'ward': ward,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'imageUrls': imageUrls,
      'contactPhone': contactPhone,
      'showPhone': showPhone,
      'visibilityScope': visibilityScope,
      if (targetCounty != null && targetCounty!.isNotEmpty)
        'targetCounty': targetCounty,
    };
  }

  String get formattedPrice => 'KES ${price.toStringAsFixed(0)}';
  String get formattedOriginalPrice =>
      'KES ${(originalPrice ?? price).toStringAsFixed(0)}';

  String get shortLocation => '$ward, $county';
  bool get hasDiscount => discountPercent > 0 && (originalPrice ?? 0) > price;
  bool get isLowStock => inStock && stockQuantity > 0 && stockQuantity <= 3;

  MarketplaceProduct copyWith({
    bool? savedByViewer,
    int? saveCount,
    bool? likedByViewer,
    int? likeCount,
    double? averageRating,
    int? ratingCount,
    bool? inStock,
    int? stockQuantity,
  }) {
    return MarketplaceProduct(
      id: id,
      title: title,
      description: description,
      price: price,
      originalPrice: originalPrice,
      discountPercent: discountPercent,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      inStock: inStock ?? this.inStock,
      deliveryType: deliveryType,
      deliveryFee: deliveryFee,
      estimatedDeliveryText: estimatedDeliveryText,
      category: category,
      condition: condition,
      county: county,
      constituency: constituency,
      ward: ward,
      latitude: latitude,
      longitude: longitude,
      imageUrls: imageUrls,
      contactPhone: contactPhone,
      showPhone: showPhone,
      status: status,
      moderationStatus: moderationStatus,
      createdById: createdById,
      sellerName: sellerName,
      sellerVerified: sellerVerified,
      sellerJoinedAt: sellerJoinedAt,
      viewCount: viewCount,
      chatClickCount: chatClickCount,
      saveCount: saveCount ?? this.saveCount,
      likeCount: likeCount ?? this.likeCount,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
      savedByViewer: savedByViewer ?? this.savedByViewer,
      likedByViewer: likedByViewer ?? this.likedByViewer,
      sponsored: sponsored,
      sponsorshipStatus: sponsorshipStatus,
      sponsoredFrom: sponsoredFrom,
      sponsoredUntil: sponsoredUntil,
      sponsorshipMultiplier: sponsorshipMultiplier,
      visibilityScope: visibilityScope,
      targetCounty: targetCounty,
      sellerMarketplaceBadge: sellerMarketplaceBadge,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
