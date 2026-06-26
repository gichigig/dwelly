class HelperProfile {
  final int id;
  final String fullName;
  final String firstName;
  final String lastName;
  final String? avatarUrl;
  final String? phoneNumber;
  final double helperPrice;
  final String? helperCoverageLevel;
  final String? helperCounty;
  final List<String> helperWards;
  final List<String> helperConstituencies;
  final double averageRating;
  final int reviewCount;
  final int totalHires;
  final bool canReview;

  HelperProfile({
    required this.id,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    this.avatarUrl,
    this.phoneNumber,
    required this.helperPrice,
    this.helperCoverageLevel,
    this.helperCounty,
    this.helperWards = const [],
    this.helperConstituencies = const [],
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.totalHires = 0,
    this.canReview = false,
  });

  factory HelperProfile.fromJson(Map<String, dynamic> json) {
    return HelperProfile(
      id: json['id'],
      fullName: json['fullName'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      avatarUrl: json['avatarUrl'],
      phoneNumber: json['phoneNumber'],
      helperPrice: (json['helperPrice'] ?? 0).toDouble(),
      helperCoverageLevel: json['helperCoverageLevel'],
      helperCounty: json['helperCounty'],
      helperWards: List<String>.from(json['helperWards'] ?? []),
      helperConstituencies: List<String>.from(json['helperConstituencies'] ?? []),
      averageRating: (json['averageRating'] ?? 0).toDouble(),
      reviewCount: json['reviewCount'] ?? 0,
      totalHires: json['totalHires'] ?? 0,
      canReview: json['canReview'] ?? false,
    );
  }
}
