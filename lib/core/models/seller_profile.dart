class SellerProfile {
  final int userId;
  final String sellerName;
  final bool verified;
  final String? verificationStatus;
  final DateTime? joinedAt;
  final int activeProducts;
  final int totalProducts;
  final int responseProxyScore;

  const SellerProfile({
    required this.userId,
    required this.sellerName,
    required this.verified,
    this.verificationStatus,
    this.joinedAt,
    this.activeProducts = 0,
    this.totalProducts = 0,
    this.responseProxyScore = 0,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      sellerName: (json['sellerName'] ?? '') as String,
      verified: json['verified'] == true,
      verificationStatus: json['verificationStatus'] as String?,
      joinedAt:
          json['joinedAt'] != null ? DateTime.tryParse(json['joinedAt']) : null,
      activeProducts: (json['activeProducts'] as num?)?.toInt() ?? 0,
      totalProducts: (json['totalProducts'] as num?)?.toInt() ?? 0,
      responseProxyScore: (json['responseProxyScore'] as num?)?.toInt() ?? 0,
    );
  }
}
