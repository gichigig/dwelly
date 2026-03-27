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
  final String firstName;
  final String lastName;
  final String? phone;
  final String? avatarUrl;
  final String role;
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

  User({
    this.id,
    required this.email,
    this.password,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.avatarUrl,
    this.role = 'USER',
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
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _toInt(json['id']),
      email: json['email'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'],
      avatarUrl: json['avatarUrl'],
      role: json['role'] ?? 'USER',
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'email': email,
      if (password != null) 'password': password,
      'firstName': firstName,
      'lastName': lastName,
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
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

  User copyWith({
    int? id,
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    String? role,
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
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      password: password ?? this.password,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
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
    );
  }
}

class AuthResponse {
  final String token;
  final String type;
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String? phone;
  final String role;
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

  AuthResponse({
    required this.token,
    required this.type,
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.role,
    this.authProvider = 'LOCAL',
    this.locationWard,
    this.locationConstituency,
    this.locationCounty,
    this.locationAreaName,
    this.locationLatitude,
    this.locationLongitude,
    this.fypWards = const [],
    this.fypNicknames = const [],
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] ?? '',
      type: json['type'] ?? 'Bearer',
      id: _toInt(json['id']) ?? 0,
      email: json['email'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'USER',
      authProvider: json['authProvider']?.toString() ?? 'LOCAL',
      locationWard: json['locationWard'],
      locationConstituency: json['locationConstituency'],
      locationCounty: json['locationCounty'],
      locationAreaName: json['locationAreaName'],
      locationLatitude: _toDouble(json['locationLatitude']),
      locationLongitude: _toDouble(json['locationLongitude']),
      fypWards: _toStringList(json['fypWards']),
      fypNicknames: _toStringList(json['fypNicknames']),
    );
  }

  User toUser() {
    return User(
      id: id,
      email: email,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      role: role,
      authProvider: authProvider,
      locationWard: locationWard,
      locationConstituency: locationConstituency,
      locationCounty: locationCounty,
      locationAreaName: locationAreaName,
      locationLatitude: locationLatitude,
      locationLongitude: locationLongitude,
      fypWards: fypWards,
      fypNicknames: fypNicknames,
    );
  }
}
