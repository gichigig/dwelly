class ContactMatch {
  final int userId;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? avatarUrl;
  final String? matchedIdentifier;

  ContactMatch({
    required this.userId,
    this.firstName,
    this.lastName,
    this.username,
    this.avatarUrl,
    this.matchedIdentifier,
  });

  factory ContactMatch.fromJson(Map<String, dynamic> json) {
    return ContactMatch(
      userId: json['userId'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      username: json['username'],
      avatarUrl: json['avatarUrl'],
      matchedIdentifier: json['matchedIdentifier'],
    );
  }
}
