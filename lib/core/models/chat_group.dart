class GroupMember {
  final int userId;
  final String firstName;
  final String lastName;
  final String email;
  final String? userAvatar;
  final String role;
  final String status;

  GroupMember({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.userAvatar,
    required this.role,
    required this.status,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId'] ?? 0,
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      email: json['email'] ?? '',
      userAvatar: json['userAvatar'],
      role: json['role'] ?? 'MEMBER',
      status: json['status'] ?? 'PENDING',
    );
  }
}

class ChatGroup {
  final int id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final int? rentalId;
  final int? buildingId;
  final int createdById;
  final bool adminOnlyMessage;
  final bool membersCanAdd;
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String myRole;
  final String myStatus;
  final List<GroupMember> members;

  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    this.rentalId,
    this.buildingId,
    required this.createdById,
    required this.adminOnlyMessage,
    required this.membersCanAdd,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageAt,
    required this.myRole,
    required this.myStatus,
    required this.members,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    var list = json['members'] as List? ?? [];
    List<GroupMember> membersList = list
        .map((i) => GroupMember.fromJson(i))
        .toList();

    return ChatGroup(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      avatarUrl: json['avatarUrl'],
      rentalId: json['rentalId'],
      buildingId: json['buildingId'],
      createdById: json['createdById'] ?? 0,
      adminOnlyMessage: json['adminOnlyMessage'] ?? false,
      membersCanAdd: json['membersCanAdd'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      lastMessage: json['lastMessage'],
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'])
          : null,
      myRole: json['myRole'] ?? 'MEMBER',
      myStatus: json['myStatus'] ?? 'PENDING',
      members: membersList,
    );
  }
}

class GroupMessage {
  final int id;
  final int chatGroupId;
  final int senderId;
  final String senderName;
  final String? senderUsername;
  final String? senderAvatarUrl;
  String content;
  String messageType;
  String? mediaUrl;
  final String? metadata;
  final DateTime createdAt;
  final String? clientMessageId;
  final String deliveryStatus;

  GroupMessage({
    required this.id,
    required this.chatGroupId,
    required this.senderId,
    required this.senderName,
    this.senderUsername,
    this.senderAvatarUrl,
    required this.content,
    this.messageType = 'TEXT',
    this.mediaUrl,
    this.metadata,
    required this.createdAt,
    this.clientMessageId,
    this.deliveryStatus = 'sent',
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] ?? 0,
      chatGroupId: json['chatGroupId'] ?? 0,
      senderId: json['senderId'] ?? 0,
      senderName: json['senderName'] ?? '',
      senderUsername: json['senderUsername'],
      senderAvatarUrl: json['senderAvatarUrl'],
      content: json['content'] ?? '',
      messageType: json['messageType'] ?? 'TEXT',
      mediaUrl: json['mediaUrl'] ?? json['attachmentUrl'],
      metadata: json['metadata'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      clientMessageId: json['clientMessageId']?.toString(),
      deliveryStatus: (json['deliveryStatus'] ?? 'sent').toString(),
    );
  }
}
