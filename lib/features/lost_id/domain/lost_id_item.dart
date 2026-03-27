class LostIdItem {
  final String id;
  final String idNumber;
  final String name;
  final String foundLocation;
  final String? description;
  final String contactPhone;
  final String? contactWhatsApp;
  final String? photoUrl;
  final DateTime createdAt;
  final bool isClaimed;

  const LostIdItem({
    required this.id,
    required this.idNumber,
    required this.name,
    required this.foundLocation,
    this.description,
    required this.contactPhone,
    this.contactWhatsApp,
    this.photoUrl,
    required this.createdAt,
    this.isClaimed = false,
  });

  LostIdItem copyWith({
    String? id,
    String? idNumber,
    String? name,
    String? foundLocation,
    String? description,
    String? contactPhone,
    String? contactWhatsApp,
    String? photoUrl,
    DateTime? createdAt,
    bool? isClaimed,
  }) {
    return LostIdItem(
      id: id ?? this.id,
      idNumber: idNumber ?? this.idNumber,
      name: name ?? this.name,
      foundLocation: foundLocation ?? this.foundLocation,
      description: description ?? this.description,
      contactPhone: contactPhone ?? this.contactPhone,
      contactWhatsApp: contactWhatsApp ?? this.contactWhatsApp,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      isClaimed: isClaimed ?? this.isClaimed,
    );
  }
}

