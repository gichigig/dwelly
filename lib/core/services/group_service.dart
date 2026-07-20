import 'dart:convert';
import 'api_service.dart';
import 'auth_service.dart';
import 'sqlite_cache_service.dart';
import '../models/chat_group.dart';

class GroupService {
  static Future<Map<String, dynamic>> getMyGroups({
    int page = 0,
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'my_groups_page_$page';

    Map<String, dynamic> parseData(dynamic decoded) {
      if (decoded is Map<String, dynamic>) {
        final List<dynamic> data = decoded['content'] ?? [];
        final groups = data.map((json) => ChatGroup.fromJson(json)).toList();
        return {
          'groups': groups,
          'hasMore': decoded['last'] == false,
          'page': decoded['number'] ?? 0,
        };
      } else if (decoded is List) {
        final groups = decoded.map((json) => ChatGroup.fromJson(json)).toList();
        return {'groups': groups, 'hasMore': false, 'page': 0};
      } else {
        return {'groups': <ChatGroup>[], 'hasMore': false, 'page': 0};
      }
    }

    if (!forceRefresh && page == 0) {
      final localData = await SqliteCacheService.instance.getChatCache(
        cacheKey,
      );
      if (localData != null) {
        // Fetch in background
        Future.microtask(() async {
          try {
            final response = await ApiService.timedGet(
              Uri.parse(
                '${ApiService.baseUrl}/groups/my?page=$page&size=$limit',
              ),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer ${AuthService.token}',
              },
            );
            if (response.statusCode == 200) {
              final decoded = json.decode(utf8.decode(response.bodyBytes));
              if (decoded is Map<String, dynamic>) {
                await SqliteCacheService.instance.saveChatCache(
                  cacheKey,
                  decoded,
                );
              } else if (decoded is List) {
                await SqliteCacheService.instance.saveChatCache(cacheKey, {
                  'content': decoded,
                });
              }
            }
          } catch (_) {}
        });
        return parseData(localData);
      }
    }

    try {
      final response = await ApiService.timedGet(
        Uri.parse('${ApiService.baseUrl}/groups/my?page=$page&size=$limit'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));

        if (decoded is Map<String, dynamic>) {
          await SqliteCacheService.instance.saveChatCache(cacheKey, decoded);
        } else if (decoded is List) {
          await SqliteCacheService.instance.saveChatCache(cacheKey, {
            'content': decoded,
          });
        }

        return parseData(decoded);
      } else {
        throw Exception('Failed to load groups: ${response.statusCode}');
      }
    } catch (e) {
      final localData = await SqliteCacheService.instance.getChatCache(
        cacheKey,
      );
      if (localData != null) {
        return parseData(localData);
      }
      throw Exception('Failed to reach the server.');
    }
  }

  static Future<List<ChatGroup>> getBuildingGroups(int buildingId) async {
    final response = await ApiService.timedGet(
      Uri.parse('${ApiService.baseUrl}/groups/building/$buildingId'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((json) => ChatGroup.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load building groups: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getGroupMessagesPaginated(
    int groupId, {
    int page = 0,
    int limit = 20,
  }) async {
    final response = await ApiService.timedGet(
      Uri.parse(
        '${ApiService.baseUrl}/groups/$groupId/messages?page=$page&size=$limit',
      ),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final messagesData = data['content'] as List<dynamic>? ?? [];
      final messages = messagesData
          .map((m) => GroupMessage.fromJson(m))
          .toList();
      return {
        'messages': messages,
        'hasMore': data['last'] == false,
        'page': data['number'] ?? 0,
        'totalPages': data['totalPages'] ?? 0,
      };
    } else {
      throw Exception('Failed to load group messages');
    }
  }

  static Future<ChatGroup> createGroup(
    String name, {
    String? description,
    int? rentalId,
    int? buildingId,
    bool adminOnlyMessage = false,
    bool membersCanAdd = false,
  }) async {
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/groups'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
      body: json.encode({
        'name': name,
        if (description != null) 'description': description,
        if (rentalId != null) 'rentalId': rentalId,
        if (buildingId != null) 'buildingId': buildingId,
        'adminOnlyMessage': adminOnlyMessage,
        'membersCanAdd': membersCanAdd,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      await SqliteCacheService.instance.removeChatCache('my_groups_page_0');
      return ChatGroup.fromJson(data);
    } else {
      throw Exception('Failed to create group: ${response.statusCode}');
    }
  }

  static Future<ChatGroup> updateGroupAvatar(
    int groupId,
    String avatarUrl,
  ) async {
    final response = await ApiService.timedPatch(
      Uri.parse('${ApiService.baseUrl}/groups/$groupId/avatar'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
      body: json.encode({'avatarUrl': avatarUrl}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      return ChatGroup.fromJson(data);
    } else {
      throw Exception('Failed to update avatar: ${response.statusCode}');
    }
  }

  static Future<void> addMember(
    int groupId,
    String identifier, {
    String role = 'MEMBER',
  }) async {
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/groups/$groupId/members'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
      body: json.encode({'identifier': identifier, 'role': role}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add member: ${response.statusCode}');
    }
  }

  static Future<ChatGroup> getGroupDetails(int groupId) async {
    final response = await ApiService.timedGet(
      Uri.parse('${ApiService.baseUrl}/groups/$groupId'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      return ChatGroup.fromJson(data);
    } else {
      throw Exception('Failed to load group details: ${response.statusCode}');
    }
  }

  static Future<GroupMessage> sendGroupMessage(
    int groupId,
    String content, {
    String messageType = 'TEXT',
    String? mediaUrl,
    String? metadata,
  }) async {
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/groups/$groupId/messages'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
      body: json.encode({
        'content': content,
        'messageType': messageType,
        if (mediaUrl != null) 'attachmentUrl': mediaUrl,
        if (metadata != null) 'metadata': metadata,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      return GroupMessage.fromJson(data);
    } else {
      throw Exception('Failed to send group message: ${response.statusCode}');
    }
  }

  static Future<void> deleteMessage(
    int groupId,
    int messageId, {
    bool deleteForAll = false,
  }) async {
    final response = await ApiService.timedDelete(
      Uri.parse(
        '${ApiService.baseUrl}/groups/$groupId/messages/$messageId?deleteForAll=$deleteForAll',
      ),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete group message: ${response.statusCode}');
    }
  }

  static Future<void> voteOnPoll(
    int groupId,
    int messageId,
    String optionId,
  ) async {
    final response = await ApiService.timedPost(
      Uri.parse(
        '${ApiService.baseUrl}/groups/$groupId/messages/$messageId/vote',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      },
      body: json.encode({'optionId': optionId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to vote: ${response.statusCode}');
    }
  }
}
