class CallInviteModel {
  final String roomName;
  final int callerId;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;
  final int? conversationId;
  final String? token;
  final String? livekitUrl;

  const CallInviteModel({
    required this.roomName,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.isVideo,
    this.conversationId,
    this.token,
    this.livekitUrl,
  });

  factory CallInviteModel.fromJson(Map<String, dynamic> json) {
    return CallInviteModel(
      roomName: json['roomName']?.toString() ?? json['room_name']?.toString() ?? '',
      callerId: int.tryParse(json['callerId']?.toString() ?? json['caller_id']?.toString() ?? '0') ?? 0,
      callerName: json['callerName']?.toString() ?? json['caller_name']?.toString() ?? 'Unknown Caller',
      callerAvatar: json['callerAvatar']?.toString() ?? json['caller_avatar']?.toString(),
      isVideo: json['isVideo'] == true || json['isVideo']?.toString() == 'true' || json['is_video'] == true || json['is_video']?.toString() == 'true',
      conversationId: int.tryParse(json['conversationId']?.toString() ?? json['conversation_id']?.toString() ?? ''),
      token: json['token']?.toString(),
      livekitUrl: json['livekitUrl']?.toString() ?? json['livekit_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomName': roomName,
      'callerId': callerId,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'isVideo': isVideo,
      'conversationId': conversationId,
      'token': token,
      'livekitUrl': livekitUrl,
    };
  }
}
