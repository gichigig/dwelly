class ChatMessage {
  final int? id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String? senderUsername;
  final String? senderAvatarUrl;
  final String? clientMessageId;
  String content;
  String messageType; // TEXT, VIDEO, SAFETY_WARNING
  String? mediaUrl;
  String? localPath; // Local file path after download
  final DateTime createdAt;
  bool isRead;
  final String deliveryStatus; // pending | sent | failed | SENT(from server)

  ChatMessage({
    this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    this.senderUsername,
    this.senderAvatarUrl,
    this.clientMessageId,
    required this.content,
    this.messageType = 'TEXT',
    this.mediaUrl,
    this.localPath,
    required this.createdAt,
    this.isRead = false,
    this.deliveryStatus = 'sent',
  });

  bool get isVideo => messageType == 'VIDEO';
  bool get isListingShare => messageType == 'LISTING_SHARE';
  bool get isLocalPending => deliveryStatus.toLowerCase() == 'pending';
  bool get isFailed => deliveryStatus.toLowerCase() == 'failed';
  bool get isSent =>
      deliveryStatus.toLowerCase() == 'sent' ||
      deliveryStatus.toUpperCase() == 'SENT';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      conversationId: json['conversationId'] ?? 0,
      senderId: json['senderId'] ?? 0,
      senderName: json['senderName'] ?? '',
      senderUsername: json['senderUsername'],
      senderAvatarUrl: json['senderAvatarUrl'],
      clientMessageId: json['clientMessageId']?.toString(),
      content: json['content'] ?? '',
      messageType: json['messageType'] ?? 'TEXT',
      mediaUrl: json['mediaUrl'],
      createdAt: _parseDateTime(json['createdAt']),
      isRead: json['isRead'] ?? false,
      deliveryStatus: (json['deliveryStatus'] ?? 'sent').toString(),
    );
  }

  static DateTime _parseDateTime(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc();
    final str = raw.toString();
    try {
      final parsed = DateTime.parse(str);
      return parsed.toUtc();
    } catch (_) {
      return DateTime.now().toUtc();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      if (senderUsername != null) 'senderUsername': senderUsername,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      'content': content,
      'messageType': messageType,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'deliveryStatus': deliveryStatus,
    };
  }
}

class Conversation {
  final int? id;
  final String listingType;
  final int? listingId;
  final String? listingTitle;
  final String? listingImageUrl;
  final int rentalId;
  final String rentalTitle;
  final int userId;
  final String userName;
  final String? userUsername;
  final String? userAvatarUrl;
  final int ownerId;
  final String ownerName;
  final String? ownerUsername;
  final String? ownerAvatarUrl;
  final bool mutedByMe;
  final bool blockedByMe;
  final bool blockedMe;
  final String? lastMessage;
  final int? lastMessageSenderId;
  final bool? lastMessageIsRead;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  Conversation({
    this.id,
    this.listingType = 'RENTAL',
    this.listingId,
    this.listingTitle,
    this.listingImageUrl,
    required this.rentalId,
    required this.rentalTitle,
    required this.userId,
    required this.userName,
    this.userUsername,
    this.userAvatarUrl,
    required this.ownerId,
    required this.ownerName,
    this.ownerUsername,
    this.ownerAvatarUrl,
    this.mutedByMe = false,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.lastMessage,
    this.lastMessageSenderId,
    this.lastMessageIsRead,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final listingType = (json['listingType'] ?? 'RENTAL').toString();
    final listingId = json['listingId'] as int?;
    final listingTitle = json['listingTitle'] as String?;
    return Conversation(
      id: json['id'],
      listingType: listingType,
      listingId: listingId,
      listingTitle: listingTitle,
      listingImageUrl: json['listingImageUrl'] as String?,
      rentalId: json['rentalId'] ?? 0,
      rentalTitle: json['rentalTitle'] ?? '',
      userId: json['userId'] ?? 0,
      userName: json['userName'] ?? '',
      userUsername: json['userUsername'],
      userAvatarUrl: json['userAvatarUrl'],
      ownerId: json['ownerId'] ?? 0,
      ownerName: json['ownerName'] ?? '',
      ownerUsername: json['ownerUsername'],
      ownerAvatarUrl: json['ownerAvatarUrl'],
      mutedByMe: json['mutedByMe'] == true,
      blockedByMe: json['blockedByMe'] == true,
      blockedMe: json['blockedMe'] == true,
      lastMessage: json['lastMessage'],
      lastMessageSenderId: json['lastMessageSenderId'],
      lastMessageIsRead: json['lastMessageIsRead'],
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'listingType': listingType,
      if (listingId != null) 'listingId': listingId,
      if (listingTitle != null) 'listingTitle': listingTitle,
      if (listingImageUrl != null) 'listingImageUrl': listingImageUrl,
      'rentalId': rentalId,
      'rentalTitle': rentalTitle,
      'userId': userId,
      'userName': userName,
      if (userUsername != null) 'userUsername': userUsername,
      'ownerId': ownerId,
      'ownerName': ownerName,
      if (ownerUsername != null) 'ownerUsername': ownerUsername,
      'mutedByMe': mutedByMe,
      'blockedByMe': blockedByMe,
      'blockedMe': blockedMe,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageAt != null)
        'lastMessageAt': lastMessageAt!.toIso8601String(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class ChatSafetyStatus {
  final bool mutedByMe;
  final bool blockedByMe;
  final bool blockedMe;

  const ChatSafetyStatus({
    required this.mutedByMe,
    required this.blockedByMe,
    required this.blockedMe,
  });

  const ChatSafetyStatus.none()
    : mutedByMe = false,
      blockedByMe = false,
      blockedMe = false;

  factory ChatSafetyStatus.fromJson(Map<String, dynamic> json) {
    return ChatSafetyStatus(
      mutedByMe: json['mutedByMe'] == true,
      blockedByMe: json['blockedByMe'] == true,
      blockedMe: json['blockedMe'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mutedByMe': mutedByMe,
      'blockedByMe': blockedByMe,
      'blockedMe': blockedMe,
    };
  }
}

class ChatSafetyContact {
  final int targetUserId;
  final String targetName;
  final String? targetEmail;
  final String? targetAvatarUrl;
  final bool muted;
  final bool blocked;
  final DateTime? updatedAt;

  const ChatSafetyContact({
    required this.targetUserId,
    required this.targetName,
    this.targetEmail,
    this.targetAvatarUrl,
    required this.muted,
    required this.blocked,
    this.updatedAt,
  });

  factory ChatSafetyContact.fromJson(Map<String, dynamic> json) {
    return ChatSafetyContact(
      targetUserId: (json['targetUserId'] as num?)?.toInt() ?? 0,
      targetName: (json['targetName'] ?? '').toString(),
      targetEmail: json['targetEmail']?.toString(),
      targetAvatarUrl: json['targetAvatarUrl']?.toString(),
      muted: json['muted'] == true,
      blocked: json['blocked'] == true,
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.tryParse(json['updatedAt'].toString()),
    );
  }
}

class ChatSafetyContactsPage {
  final List<ChatSafetyContact> contacts;
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final bool hasMore;

  const ChatSafetyContactsPage({
    required this.contacts,
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.hasMore,
  });

  factory ChatSafetyContactsPage.fromJson(Map<String, dynamic> json) {
    final rawContacts = json['contacts'] as List<dynamic>? ?? const [];
    return ChatSafetyContactsPage(
      contacts: rawContacts
          .map((e) => ChatSafetyContact.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] == true,
    );
  }
}
