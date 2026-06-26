double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

List<String> _toStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList();
}

class User {
  final int? id;
  final String email;
  final String? password;
  final String? username;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final String? primaryRole;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String authProvider;

  // User location (reverse geocoded)
  final String? locationWard;
  final String? locationConstituency;
  final String? locationCounty;
  final String? locationAreaName;
  final double? locationLatitude;
  final double? locationLongitude;

  // FYP (For You Page) preferences
  final List<String> fypWards; // Up to 5 preferred wards
  final List<String> fypNicknames; // Unlimited area nicknames

  // Premium subscription
  final DateTime? premiumStartedAt;
  final DateTime? premiumExpiresAt;

  // RealAdmin Pro (only removes ads in Dwelly)
  final DateTime? realadminPremiumStartedAt;
  final DateTime? realadminPremiumExpiresAt;

  // Helper data
  final String? helperCoverageLevel;
  final String? helperCounty;
  final List<String> helperConstituencies;
  final List<String> helperWards;
  final double? helperPrice;
  final double? helperBalance;
  final double? helperTotalEarned;

  User({
    this.id,
    required this.email,
    this.password,
    this.username,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.avatarUrl,
    this.role = 'USER',
    this.primaryRole,
    this.enabled = true,
    this.authProvider = 'LOCAL',
    this.createdAt,
    this.updatedAt,
    this.locationWard,
    this.locationConstituency,
    this.locationCounty,
    this.locationAreaName,
    this.locationLatitude,
    this.locationLongitude,
    this.fypWards = const [],
    this.fypNicknames = const [],
    this.premiumStartedAt,
    this.premiumExpiresAt,
    this.realadminPremiumStartedAt,
    this.realadminPremiumExpiresAt,
    this.helperCoverageLevel,
    this.helperCounty,
    this.helperConstituencies = const [],
    this.helperWards = const [],
    this.helperPrice,
    this.helperBalance,
    this.helperTotalEarned,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _toInt(json['id']),
      email: json['email'] ?? '',
      username: json['username'],
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'],
      avatarUrl: json['avatarUrl'],
      role: json['role'] ?? 'USER',
      primaryRole: json['primaryRole'],
      enabled: json['enabled'] ?? true,
      authProvider: json['authProvider']?.toString() ?? 'LOCAL',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      locationWard: json['locationWard'],
      locationConstituency: json['locationConstituency'],
      locationCounty: json['locationCounty'],
      locationAreaName: json['locationAreaName'],
      locationLatitude: _toDouble(json['locationLatitude']),
      locationLongitude: _toDouble(json['locationLongitude']),
      fypWards: _toStringList(json['fypWards']),
      fypNicknames: _toStringList(json['fypNicknames']),
      premiumStartedAt: json['premiumStartedAt'] != null
          ? DateTime.tryParse(json['premiumStartedAt'].toString())
          : null,
      premiumExpiresAt: json['premiumExpiresAt'] != null
          ? DateTime.tryParse(json['premiumExpiresAt'].toString())
          : null,
      realadminPremiumStartedAt: json['realadminPremiumStartedAt'] != null
          ? DateTime.tryParse(json['realadminPremiumStartedAt'].toString())
          : null,
      realadminPremiumExpiresAt: json['realadminPremiumExpiresAt'] != null
          ? DateTime.tryParse(json['realadminPremiumExpiresAt'].toString())
          : null,
      helperCoverageLevel: json['helperCoverageLevel']?.toString(),
      helperCounty: json['helperCounty']?.toString(),
      helperConstituencies: _toStringList(json['helperConstituencies']),
      helperWards: _toStringList(json['helperWards']),
      helperPrice: _toDouble(json['helperPrice']),
      helperBalance: _toDouble(json['helperBalance']),
      helperTotalEarned: _toDouble(json['helperTotalEarned']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'email': email,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      'firstName': firstName,
      'lastName': lastName,
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'role': role,
      if (primaryRole != null) 'primaryRole': primaryRole,
      'authProvider': authProvider,
      if (locationWard != null) 'locationWard': locationWard,
      if (locationConstituency != null)
        'locationConstituency': locationConstituency,
      if (locationCounty != null) 'locationCounty': locationCounty,
      if (locationAreaName != null) 'locationAreaName': locationAreaName,
      if (locationLatitude != null) 'locationLatitude': locationLatitude,
      if (locationLongitude != null) 'locationLongitude': locationLongitude,
      'fypWards': fypWards,
      'fypNicknames': fypNicknames,
      if (premiumStartedAt != null)
        'premiumStartedAt': premiumStartedAt!.toIso8601String(),
      if (premiumExpiresAt != null)
        'premiumExpiresAt': premiumExpiresAt!.toIso8601String(),
      if (realadminPremiumStartedAt != null)
        'realadminPremiumStartedAt': realadminPremiumStartedAt!.toIso8601String(),
      if (realadminPremiumExpiresAt != null)
        'realadminPremiumExpiresAt': realadminPremiumExpiresAt!.toIso8601String(),
      if (helperCoverageLevel != null) 'helperCoverageLevel': helperCoverageLevel,
      if (helperCounty != null) 'helperCounty': helperCounty,
      'helperConstituencies': helperConstituencies,
      'helperWards': helperWards,
      if (helperPrice != null) 'helperPrice': helperPrice,
      if (helperBalance != null) 'helperBalance': helperBalance,
      if (helperTotalEarned != null) 'helperTotalEarned': helperTotalEarned,
    };
  }

  String get fullName => '$firstName $lastName';

  /// Get formatted location string
  String get formattedLocation {
    final parts = <String>[];
    if (locationAreaName != null && locationAreaName!.isNotEmpty) {
      parts.add(locationAreaName!);
    } else if (locationWard != null && locationWard!.isNotEmpty) {
      parts.add(locationWard!);
    }
    if (locationConstituency != null && locationConstituency!.isNotEmpty) {
      parts.add(locationConstituency!);
    }
    if (locationCounty != null && locationCounty!.isNotEmpty) {
      parts.add(locationCounty!);
    }
    return parts.isEmpty ? 'Location not set' : parts.join(', ');
  }

  bool get hasLocation =>
      locationWard != null ||
      locationConstituency != null ||
      locationCounty != null;

  bool get hasFypPreferences => fypWards.isNotEmpty || fypNicknames.isNotEmpty;

  bool get isPremiumActive =>
      premiumExpiresAt != null && premiumExpiresAt!.isAfter(DateTime.now());

  bool get isRealadminPremiumActive =>
      realadminPremiumExpiresAt != null &&
      realadminPremiumExpiresAt!.isAfter(DateTime.now());

  bool get shouldHideAds => isPremiumActive || isRealadminPremiumActive;

  User copyWith({
    int? id,
    String? email,
    String? password,
    String? username,
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    String? role,
    String? primaryRole,
    bool? enabled,
    String? authProvider,
    String? locationWard,
    String? locationConstituency,
    String? locationCounty,
    String? locationAreaName,
    double? locationLatitude,
    double? locationLongitude,
    List<String>? fypWards,
    List<String>? fypNicknames,
    DateTime? premiumStartedAt,
    DateTime? premiumExpiresAt,
    DateTime? realadminPremiumStartedAt,
    DateTime? realadminPremiumExpiresAt,
    String? helperCoverageLevel,
    String? helperCounty,
    List<String>? helperConstituencies,
    List<String>? helperWards,
    double? helperPrice,
    double? helperBalance,
    double? helperTotalEarned,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      password: password ?? this.password,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      primaryRole: primaryRole ?? this.primaryRole,
      enabled: enabled ?? this.enabled,
      authProvider: authProvider ?? this.authProvider,
      createdAt: createdAt,
      updatedAt: updatedAt,
      locationWard: locationWard ?? this.locationWard,
      locationConstituency: locationConstituency ?? this.locationConstituency,
      locationCounty: locationCounty ?? this.locationCounty,
      locationAreaName: locationAreaName ?? this.locationAreaName,
      locationLatitude: locationLatitude ?? this.locationLatitude,
      locationLongitude: locationLongitude ?? this.locationLongitude,
      fypWards: fypWards ?? this.fypWards,
      fypNicknames: fypNicknames ?? this.fypNicknames,
      premiumStartedAt: premiumStartedAt ?? this.premiumStartedAt,
      premiumExpiresAt: premiumExpiresAt ?? this.premiumExpiresAt,
      realadminPremiumStartedAt: realadminPremiumStartedAt ?? this.realadminPremiumStartedAt,
      realadminPremiumExpiresAt: realadminPremiumExpiresAt ?? this.realadminPremiumExpiresAt,
      helperCoverageLevel: helperCoverageLevel ?? this.helperCoverageLevel,
      helperCounty: helperCounty ?? this.helperCounty,
      helperConstituencies: helperConstituencies ?? this.helperConstituencies,
      helperWards: helperWards ?? this.helperWards,
      helperPrice: helperPrice ?? this.helperPrice,
      helperBalance: helperBalance ?? this.helperBalance,
      helperTotalEarned: helperTotalEarned ?? this.helperTotalEarned,
    );
  }
}

class AuthResponse {
  final String token;
  final String? refreshToken;
  final String type;
  final int id;
  final String email;
  final String? username;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final String? primaryRole;
  final String authProvider;

  // Location fields
  final String? locationWard;
  final String? locationConstituency;
  final String? locationCounty;
  final String? locationAreaName;
  final double? locationLatitude;
  final double? locationLongitude;

  // FYP preferences
  final List<String> fypWards;
  final List<String> fypNicknames;

  // Premium subscription
  final DateTime? premiumStartedAt;
  final DateTime? premiumExpiresAt;

  // RealAdmin Pro
  final DateTime? realadminPremiumStartedAt;
  final DateTime? realadminPremiumExpiresAt;

  AuthResponse({
    required this.token,
    this.refreshToken,
    required this.type,
    required this.id,
    required this.email,
    this.username,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.avatarUrl,
    required this.role,
    this.primaryRole,
    this.authProvider = 'LOCAL',
    this.locationWard,
    this.locationConstituency,
    this.locationCounty,
    this.locationAreaName,
    this.locationLatitude,
    this.locationLongitude,
    this.fypWards = const [],
    this.fypNicknames = const [],
    this.premiumStartedAt,
    this.premiumExpiresAt,
    this.realadminPremiumStartedAt,
    this.realadminPremiumExpiresAt,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'],
      type: json['type'] ?? 'Bearer',
      id: _toInt(json['id']) ?? 0,
      email: json['email'] ?? '',
      username: json['username'],
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'],
      avatarUrl: json['avatarUrl'],
      role: json['role'] ?? 'USER',
      primaryRole: json['primaryRole'],
      authProvider: json['authProvider']?.toString() ?? 'LOCAL',
      locationWard: json['locationWard'],
      locationConstituency: json['locationConstituency'],
      locationCounty: json['locationCounty'],
      locationAreaName: json['locationAreaName'],
      locationLatitude: _toDouble(json['locationLatitude']),
      locationLongitude: _toDouble(json['locationLongitude']),
      fypWards: _toStringList(json['fypWards']),
      fypNicknames: _toStringList(json['fypNicknames']),
      premiumStartedAt: json['premiumStartedAt'] != null
          ? DateTime.tryParse(json['premiumStartedAt'].toString())
          : null,
      premiumExpiresAt: json['premiumExpiresAt'] != null
          ? DateTime.tryParse(json['premiumExpiresAt'].toString())
          : null,
      realadminPremiumStartedAt: json['realadminPremiumStartedAt'] != null
          ? DateTime.tryParse(json['realadminPremiumStartedAt'].toString())
          : null,
      realadminPremiumExpiresAt: json['realadminPremiumExpiresAt'] != null
          ? DateTime.tryParse(json['realadminPremiumExpiresAt'].toString())
          : null,
    );
  }

  User toUser() {
    return User(
      id: id,
      email: email,
      username: username,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      avatarUrl: avatarUrl,
      role: role,
      primaryRole: primaryRole,
      authProvider: authProvider,
      locationWard: locationWard,
      locationConstituency: locationConstituency,
      locationCounty: locationCounty,
      locationAreaName: locationAreaName,
      locationLatitude: locationLatitude,
      locationLongitude: locationLongitude,
      fypWards: fypWards,
      fypNicknames: fypNicknames,
      premiumStartedAt: premiumStartedAt,
      premiumExpiresAt: premiumExpiresAt,
      realadminPremiumStartedAt: realadminPremiumStartedAt,
      realadminPremiumExpiresAt: realadminPremiumExpiresAt,
    );
  }
}
