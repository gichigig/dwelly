class MarketplaceReview {
  final int id;
  final int productId;
  final int userId;
  final String userName;
  final bool userMarketplaceBadge;
  final int rating;
  final String? comment;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool mine;

  const MarketplaceReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    required this.userMarketplaceBadge,
    required this.rating,
    this.comment,
    required this.status,
    this.createdAt,
    this.updatedAt,
    required this.mine,
  });

  factory MarketplaceReview.fromJson(Map<String, dynamic> json) {
    return MarketplaceReview(
      id: (json['id'] as num?)?.toInt() ?? 0,
      productId: (json['productId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: (json['userName'] ?? '') as String,
      userMarketplaceBadge: json['userMarketplaceBadge'] == true,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      status: (json['status'] ?? 'VISIBLE') as String,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      mine: json['mine'] == true,
    );
  }
}

class MarketplaceReviewPage {
  final List<MarketplaceReview> reviews;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final int pageSize;
  final bool hasMore;

  const MarketplaceReviewPage({
    required this.reviews,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
    required this.hasMore,
  });
}
