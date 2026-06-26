class HelperReview {
  final int id;
  final int helperId;
  final int clientId;
  final String clientName;
  final String? clientAvatarUrl;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  HelperReview({
    required this.id,
    required this.helperId,
    required this.clientId,
    required this.clientName,
    this.clientAvatarUrl,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory HelperReview.fromJson(Map<String, dynamic> json) {
    return HelperReview(
      id: json['id'],
      helperId: json['helperId'],
      clientId: json['clientId'],
      clientName: json['clientName'] ?? 'Anonymous',
      clientAvatarUrl: json['clientAvatarUrl'],
      rating: json['rating'] ?? 5,
      comment: json['comment'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
