import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../core/models/chat_group.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/group_service.dart';
import '../../../core/services/sqlite_cache_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/chat_realtime_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/widgets/full_screen_image_view.dart';
import 'contacts_list_page.dart';
import '../../user_profile/presentation/user_public_profile_page.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io';
import '../../../core/services/api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class GroupChatPage extends StatefulWidget {
  final ChatGroup group;

  const GroupChatPage({super.key, required this.group});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  late ChatGroup _group;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  Timer? _pollingTimer;
  final _realtimeService = ChatRealtimeService();
  bool _isRealtimeConnected = false;
  StompUnsubscribe? _messagesUnsubscribe;
  StompUnsubscribe? _detailsUnsubscribe;

  bool _isEmojiPickerVisible = false;
  final FocusNode _focusNode = FocusNode();

  // Pagination state
  int _currentPage = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  static const int _messagesPerPage = 20;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isEmojiPickerVisible) {
        setState(() {
          _isEmojiPickerVisible = false;
        });
      }
    });
    _scrollController.addListener(_onScroll);
    _loadMessages();
    _refreshGroupDetails();
    _startPolling();
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    final currentUserId = AuthService.currentUser?.id;
    if (currentUserId == null) return;

    await _realtimeService.connect(
      onConnected: () {
        if (!mounted) return;
        setState(() => _isRealtimeConnected = true);

        _messagesUnsubscribe?.call();
        _messagesUnsubscribe = _realtimeService.subscribeGroupMessages(
          _group.id,
          (newMsg) {
            if (!mounted) return;
            setState(() {
              final exists = _messages.any((m) =>
                  m.id == newMsg.id ||
                  (m.clientMessageId != null &&
                      m.clientMessageId == newMsg.clientMessageId));
              if (!exists) {
                _messages.add(newMsg);
              }
            });
            _scrollToBottom();
          },
        );

        _detailsUnsubscribe?.call();
        _detailsUnsubscribe = _realtimeService.subscribeGroupDetails(
          _group.id,
          (updatedGroup) {
            if (!mounted) return;
            setState(() {
              _group = updatedGroup;
            });
          },
        );

        // Thundering herd protection: check if reconnecting after a significant drop (>= 5s)
        final lastDisconnect = _realtimeService.lastDisconnectedAt;
        _realtimeService.clearDisconnectTimestamp();
        if (lastDisconnect != null &&
            DateTime.now().difference(lastDisconnect).inSeconds >= 5) {
          // Add query smoothing jitter (0-1.5s) before catch-up REST sync
          Future.delayed(Duration(milliseconds: Random().nextInt(1500)), () {
            if (mounted && _isRealtimeConnected) {
              _pollForNewMessages();
            }
          });
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isRealtimeConnected = false);
      },
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messagesUnsubscribe?.call();
    _detailsUnsubscribe?.call();
    _realtimeService.disconnect();
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 150 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        !_isLoading) {
      _loadMoreMessages();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isRealtimeConnected) return;
      _pollForNewMessages();
      _refreshGroupDetails();
    });
  }

  Future<void> _refreshGroupDetails() async {
    if (_isRealtimeConnected) return;
    try {
      final freshGroup = await GroupService.getGroupDetails(_group.id);
      if (mounted) {
        setState(() {
          _group = freshGroup;
        });
      }
    } catch (e) {
      debugPrint('Failed to refresh group details: $e');
    }
  }

  void _showContactOptionsDialog(
    int userId,
    String currentName,
    String? username,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          ContactService.getDisplayName(
            userId,
            currentName,
            username: username,
          ),
        ),
        content: const Text('Choose an option:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPublicProfilePage(userId: userId),
                ),
              );
            },
            child: const Text('View Profile'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSaveContactFormDialog(userId, currentName, username);
            },
            child: const Text('Save Contact'),
          ),
        ],
      ),
    );
  }

  void _showSaveContactFormDialog(
    int userId,
    String currentName,
    String? username,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Contact'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Contact Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await ContactService.saveContact(
                  userId: userId,
                  customName: newName,
                  username: username,
                );
                if (mounted) {
                  setState(() {});
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pollForNewMessages() async {
    if (_isRealtimeConnected || _isLoading || _isSending) return;

    try {
      final result = await GroupService.getGroupMessagesPaginated(
        _group.id,
        page: 0,
        limit: _messagesPerPage,
      );
      final latestMessages = List<GroupMessage>.from(result['messages'] ?? []);
      if (latestMessages.isEmpty) return;

      bool changed = false;
      final updatedMessages = List<GroupMessage>.from(_messages);

      for (final message in latestMessages) {
        final existingIndex = updatedMessages.indexWhere(
          (m) =>
              m.id == message.id ||
              (m.clientMessageId != null &&
                  m.clientMessageId == message.clientMessageId),
        );

        if (existingIndex >= 0) {
          if (updatedMessages[existingIndex].metadata != message.metadata ||
              updatedMessages[existingIndex].content != message.content ||
              updatedMessages[existingIndex].mediaUrl != message.mediaUrl) {
            updatedMessages[existingIndex] = message;
            changed = true;
          }
        } else {
          updatedMessages.add(message);
          changed = true;
        }
      }

      if (changed) {
        final wasAtBottom =
            _scrollController.hasClients &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 100;
        setState(() {
          _messages = updatedMessages
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        if (wasAtBottom) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
      _hasMoreMessages = true;
    });

    try {
      final result = await GroupService.getGroupMessagesPaginated(
        _group.id,
        page: 0,
        limit: _messagesPerPage,
      );
      final messages = List<GroupMessage>.from(result['messages'] ?? []);
      final hasMore = result['hasMore'] == true;

      setState(() {
        _messages = messages
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _hasMoreMessages = hasMore;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _error = 'Failed to load messages.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() {
      _isLoadingMore = true;
    });

    final previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final previousMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    try {
      final nextPage = _currentPage + 1;
      final result = await GroupService.getGroupMessagesPaginated(
        _group.id,
        page: nextPage,
        limit: _messagesPerPage,
      );
      final olderMessages = List<GroupMessage>.from(result['messages'] ?? []);
      final hasMore = result['hasMore'] == true;

      setState(() {
        final existingIds = _messages.map((m) => m.id).whereType<int>().toSet();
        final uniqueOlder = olderMessages
            .where((m) => m.id == null || !existingIds.contains(m.id))
            .toList();
        _messages = [...uniqueOlder, ..._messages];
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _currentPage = nextPage;
        _hasMoreMessages = hasMore;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - previousMaxExtent;
        _scrollController.jumpTo(previousOffset + delta);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load more messages')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _sendMessage({
    String content = '',
    String messageType = 'TEXT',
    String? mediaUrl,
    String? metadata,
  }) async {
    final text = content.isEmpty ? _messageController.text.trim() : content;
    if (text.isEmpty && mediaUrl == null && metadata == null) return;

    // Check if user is approved and if adminOnly restricts them
    final myMember = _group.members.firstWhere(
      (m) => m.userId == AuthService.currentUser?.id,
      orElse: () => GroupMember(
        userId: AuthService.currentUser?.id ?? 0,
        firstName: '',
        lastName: '',
        email: '',
        role: 'MEMBER',
        status: 'PENDING',
      ),
    );

    if (myMember.status != 'APPROVED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your membership is not approved yet')),
      );
      return;
    }

    if (_group.adminOnlyMessage && myMember.role != 'ADMIN') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can send messages in this group'),
        ),
      );
      return;
    }

    final clientMessageId = _uuid.v4();
    final pendingMessage = GroupMessage(
      id: -1,
      chatGroupId: _group.id,
      senderId: AuthService.currentUser?.id ?? 0,
      senderName: AuthService.currentUser?.fullName ?? 'You',
      senderUsername: AuthService.currentUser?.username,
      content: text,
      messageType: messageType,
      mediaUrl: mediaUrl,
      metadata: metadata,
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
      deliveryStatus: 'pending',
    );

    setState(() {
      _isSending = true;
      _messages.add(pendingMessage);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final result = await GroupService.sendGroupMessage(
        _group.id,
        text,
        messageType: messageType,
        mediaUrl: mediaUrl,
        metadata: metadata,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere(
          (m) => m.clientMessageId == clientMessageId,
        );
        if (index >= 0) {
          _messages[index] = result;
        } else {
          _messages.add(result);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere(
          (m) => m.clientMessageId == clientMessageId,
        );
        if (index >= 0) {
          final failed = _messages[index];
          _messages[index] = GroupMessage(
            id: failed.id,
            chatGroupId: failed.chatGroupId,
            senderId: failed.senderId,
            senderName: failed.senderName,
            senderUsername: failed.senderUsername,
            content: failed.content,
            messageType: failed.messageType,
            mediaUrl: failed.mediaUrl,
            metadata: failed.metadata,
            createdAt: failed.createdAt,
            clientMessageId: failed.clientMessageId,
            deliveryStatus: 'failed',
          );
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send message.')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _deleteMessage(
    GroupMessage message, {
    bool deleteForAll = false,
  }) async {
    if (message.id < 0) return;
    try {
      await GroupService.deleteMessage(
        _group.id,
        message.id,
        deleteForAll: deleteForAll,
      );
      if (mounted) {
        setState(() {
          if (deleteForAll) {
            message.content = 'This message was deleted';
            message.messageType = 'DELETED';
            message.mediaUrl = null;
          } else {
            _messages.removeWhere((m) => m.id == message.id);
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
      }
    }
  }

  Future<void> _updateGroupImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final url = await ApiService.uploadFile(
        File(xfile.path),
        '/files/upload',
        token: AuthService.token,
      );
      final updatedGroup = await GroupService.updateGroupAvatar(_group.id, url);
      if (mounted) {
        setState(() {
          _group = updatedGroup;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update group image: $e')),
        );
      }
    }
  }

  void _showGroupDetails() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _group.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_group.description != null &&
                  _group.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _group.description!,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _group.members.length,
                  itemBuilder: (context, index) {
                    final member = _group.members[index];
                    final displayName =
                        '${member.firstName} ${member.lastName}';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            member.userAvatar != null &&
                                member.userAvatar!.isNotEmpty
                            ? CachedNetworkImageProvider(
                                    ApiService.resolveMediaUrl(
                                      member.userAvatar!,
                                    )!,
                                  )
                                  as ImageProvider
                            : null,
                        child:
                            member.userAvatar == null ||
                                member.userAvatar!.isEmpty
                            ? Text(
                                member.firstName.isNotEmpty
                                    ? member.firstName[0].toUpperCase()
                                    : '?',
                              )
                            : null,
                      ),
                      title: Text(displayName),
                      subtitle: Text(member.role),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                UserPublicProfilePage(userId: member.userId),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showCreatePollDialog() {
    final questionController = TextEditingController();
    final optionsControllers = [
      TextEditingController(),
      TextEditingController(),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Create Poll'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: questionController,
                      decoration: const InputDecoration(labelText: 'Question'),
                    ),
                    const SizedBox(height: 16),
                    ...optionsControllers.asMap().entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.value,
                                decoration: InputDecoration(
                                  labelText: 'Option ${entry.key + 1}',
                                ),
                              ),
                            ),
                            if (optionsControllers.length > 2)
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setState(() {
                                    optionsControllers.removeAt(entry.key);
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                    if (optionsControllers.length < 10)
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Option'),
                        onPressed: () {
                          setState(() {
                            optionsControllers.add(TextEditingController());
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (questionController.text.trim().isEmpty) return;
                    final validOptions = optionsControllers
                        .where((c) => c.text.trim().isNotEmpty)
                        .map((c) => c.text.trim())
                        .toList();
                    if (validOptions.length < 2) return;

                    Navigator.pop(context);

                    final optionsJson = validOptions.asMap().entries.map((e) {
                      return {'id': e.key.toString(), 'text': e.value};
                    }).toList();

                    final metadataJson = json.encode({
                      'question': questionController.text.trim(),
                      'options': optionsJson,
                      'votes': {},
                    });

                    await _sendMessage(
                      content: 'Created a poll',
                      messageType: 'POLL',
                      metadata: metadataJson,
                    );
                  },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.image, color: Colors.white),
                ),
                title: const Text('Gallery'),
                subtitle: const Text('Share photos or videos'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (xfile != null) {
                    await _processAndSendImage(xfile);
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(
                    source: ImageSource.camera,
                  );
                  if (xfile != null) {
                    await _processAndSendImage(xfile);
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.poll, color: Colors.white),
                ),
                title: const Text('Poll'),
                subtitle: const Text('Create a poll'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreatePollDialog();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: const Text('Contact'),
                subtitle: const Text('Share a contact'),
                onTap: () async {
                  Navigator.pop(context);
                  final status = await FlutterContacts.permissions.request(
                    PermissionType.read,
                  );
                  if (status == PermissionStatus.granted) {
                    final contact = await FlutterContacts.native.showPicker();
                    if (contact != null && contact.id != null) {
                      final fullContact = await FlutterContacts.get(
                        contact.id!,
                        properties: {ContactProperty.phone},
                      );
                      if (fullContact != null && mounted) {
                        final phone = fullContact.phones.isNotEmpty
                            ? fullContact.phones.first.number
                            : '';
                        final name = fullContact.displayName;
                        await _sendMessage(
                          content: 'Shared Contact',
                          messageType: 'CONTACT',
                          metadata: '{"name": "$name", "phone": "$phone"}',
                        );
                      }
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Contact permission denied'),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processAndSendImage(XFile xfile) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: xfile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Edit Photo'),
      ],
    );

    if (croppedFile != null && mounted) {
      String? caption = await showDialog<String>(
        context: context,
        builder: (context) {
          String input = '';
          return AlertDialog(
            title: const Text('Add Caption'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.file(File(croppedFile.path), height: 150),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (val) => input = val,
                    decoration: const InputDecoration(
                      hintText: 'Enter a caption (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, input),
                child: const Text('Send'),
              ),
            ],
          );
        },
      );

      if (caption != null && mounted) {
        setState(() => _isSending = true);
        try {
          final url = await ApiService.uploadFile(
            File(croppedFile.path),
            '/files/upload',
            token: AuthService.token,
          );
          await _sendMessage(
            content: caption.isNotEmpty ? caption : 'Sent an image',
            messageType: 'IMAGE',
            mediaUrl: url,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload image: $e')),
            );
          }
        } finally {
          if (mounted) setState(() => _isSending = false);
        }
      }
    }
  }

  void _handleAvatarTap(bool isAdmin) {
    if (_group.avatarUrl == null) {
      if (isAdmin) {
        _updateGroupImage();
      } else {
        _showGroupDetails();
      }
      return;
    }

    if (!isAdmin) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenImageView(
            imageUrl: ApiService.resolveMediaUrl(_group.avatarUrl!)!,
          ),
        ),
      );
      return;
    }

    // Is Admin and has avatar: Show options
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('View Full Image'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullScreenImageView(
                      imageUrl: ApiService.resolveMediaUrl(_group.avatarUrl!)!,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Change Image'),
              onTap: () {
                Navigator.pop(context);
                _updateGroupImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myMember = _group.members.firstWhere(
      (m) => m.userId == AuthService.currentUser?.id,
      orElse: () => GroupMember(
        userId: 0,
        firstName: '',
        lastName: '',
        email: '',
        role: 'MEMBER',
        status: '',
      ),
    );
    final isAdmin = myMember.role == 'ADMIN';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showGroupDetails,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _handleAvatarTap(isAdmin),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.tertiaryContainer,
                      backgroundImage: _group.avatarUrl != null
                          ? CachedNetworkImageProvider(
                              ApiService.resolveMediaUrl(_group.avatarUrl)!,
                            )
                          : null,
                      child: _group.avatarUrl == null
                          ? Icon(
                              Icons.group,
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                              size: 20,
                            )
                          : null,
                    ),
                    if (isAdmin)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit,
                            size: 10,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _group.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_group.members.length} members',
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Members',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const ContactsListPage(initialSelectionMode: true),
                ),
              ).then((selectedUserIds) async {
                if (selectedUserIds != null && selectedUserIds is List<int>) {
                  setState(() => _isLoading = true);
                  int addedCount = 0;
                  try {
                    for (final userId in selectedUserIds) {
                      if (userId == AuthService.currentUser?.id) continue;
                      try {
                        await GroupService.addMember(
                          _group.id,
                          userId.toString(),
                        );
                        addedCount++;
                      } catch (e) {
                        debugPrint('Failed to add member $userId: $e');
                      }
                    }
                    if (mounted && addedCount > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Successfully added $addedCount members.',
                          ),
                        ),
                      );
                      await _refreshGroupDetails();
                      await SqliteCacheService.instance.removeChatCache(
                        'my_groups_page_0',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error adding some members: $e'),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesArea()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_isLoading) {
      return const Center(child: DwellyOrbitingLoader());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            ElevatedButton(
              onPressed: _loadMessages,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet. Say hi!'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount:
          _messages.length + (_isLoadingMore || _hasMoreMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoadingMore || _hasMoreMessages) {
          if (index == 0) {
            if (_isLoadingMore) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: DwellyOrbitingLoader(),
                ),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _loadMoreMessages,
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('Load earlier messages'),
                  ),
                ),
              );
            }
          }
          index -= 1;
        }

        final message = _messages[index];
        final isMe = message.senderId == AuthService.currentUser?.id;

        return _buildMessageBubble(message, isMe);
      },
    );
  }

  Widget _buildPollBubble(GroupMessage message, bool isMe) {
    try {
      final data = json.decode(message.metadata!);
      final question = data['question'] as String? ?? 'Poll';
      final options = data['options'] as List? ?? [];
      final votes = data['votes'] as Map<String, dynamic>? ?? {};

      final totalVotes = votes.length;
      final currentUserId = AuthService.currentUser?.id.toString();

      return Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final optId = opt['id'].toString();
              final optText = opt['text'].toString();
              final voteCount = votes.values
                  .where((v) => v.toString() == optId)
                  .length;
              final progress = totalVotes > 0 ? voteCount / totalVotes : 0.0;
              final isMyVote = votes[currentUserId] == optId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () async {
                    try {
                      await GroupService.voteOnPoll(
                        _group.id,
                        message.id,
                        optId,
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to vote: $e')),
                        );
                      }
                    }
                  },
                  child: Stack(
                    children: [
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.2)
                              : Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.4)
                                : Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  optText,
                                  style: TextStyle(
                                    fontWeight: isMyVote
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isMe
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (voteCount > 0)
                                Text(
                                  '$voteCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isMe
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '$totalVotes votes',
              style: TextStyle(
                fontSize: 12,
                color: isMe
                    ? Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return const Text('Invalid poll data');
    }
  }

  Widget _buildMessageBubble(GroupMessage message, bool isMe) {
    final colorScheme = Theme.of(context).colorScheme;

    // Check if user is an admin for delete permissions
    final myMember = _group.members.firstWhere(
      (m) => m.userId == AuthService.currentUser?.id,
      orElse: () => GroupMember(
        userId: 0,
        firstName: '',
        lastName: '',
        email: '',
        role: 'MEMBER',
        status: '',
      ),
    );
    final isAdmin = myMember.role == 'ADMIN';
    final bool isMediaOnly =
        (message.messageType == 'IMAGE') &&
        (message.content.isEmpty || message.content == 'Sent an image');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Text copied')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.orange,
                    ),
                    title: const Text(
                      'Delete for me',
                      style: TextStyle(color: Colors.orange),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteMessage(message, deleteForAll: false);
                    },
                  ),
                  if (isMe || isAdmin)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Delete for everyone',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _deleteMessage(message, deleteForAll: true);
                      },
                    ),
                ],
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: isMediaOnly
              ? const EdgeInsets.all(2)
              : const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: isMediaOnly
                ? Colors.transparent
                : (isMe
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && !isMediaOnly)
                GestureDetector(
                  onTap: () => _showContactOptionsDialog(
                    message.senderId,
                    message.senderName,
                    message.senderUsername,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      ContactService.getDisplayName(
                        message.senderId,
                        message.senderName,
                        username: message.senderUsername,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.onSurfaceVariant
                            .withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              if (message.messageType == 'IMAGE' && message.mediaUrl != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: isMediaOnly ? 0 : 4,
                    bottom: isMediaOnly ? 0 : 4,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      final imageUrl = message.mediaUrl!.startsWith('http')
                          ? message.mediaUrl!
                          : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              FullScreenImageView(imageUrl: imageUrl),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isMediaOnly ? 14 : 8),
                      child: Stack(
                        children: [
                          Hero(
                            tag: message.mediaUrl!.startsWith('http')
                                ? message.mediaUrl!
                                : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}',
                            child: CachedNetworkImage(
                              imageUrl: message.mediaUrl!.startsWith('http')
                                  ? message.mediaUrl!
                                  : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${message.mediaUrl}',
                              width: isMediaOnly ? 250 : 200,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const SizedBox(
                                width: 200,
                                height: 200,
                                child: Center(child: DwellyOrbitingLoader()),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            ),
                          ),
                          if (isMediaOnly)
                            Positioned(
                              bottom: 6,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(message.createdAt),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        message.deliveryStatus == 'failed'
                                            ? Icons.error
                                            : message.deliveryStatus ==
                                                  'pending'
                                            ? Icons.schedule
                                            : Icons.done_all,
                                        size: 12,
                                        color:
                                            message.deliveryStatus == 'failed'
                                            ? Colors.red
                                            : Colors.white70,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (message.messageType == 'LIVE_LOCATION' &&
                  message.metadata != null)
                _buildLocationBubble(message, isMe)
              else if (message.messageType == 'CONTACT' &&
                  message.metadata != null)
                _buildContactBubble(message, isMe)
              else if (message.messageType == 'POLL' &&
                  message.metadata != null)
                _buildPollBubble(message, isMe)
              else if (message.messageType == 'TEXT' ||
                  (!isMediaOnly && message.messageType == 'IMAGE'))
                Linkify(
                  onOpen: (link) async {
                    final url = Uri.parse(link.url);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open link')),
                        );
                      }
                    }
                  },
                  text: message.content,
                  style: TextStyle(
                    color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                  linkStyle: TextStyle(
                    color: isMe ? colorScheme.onPrimary : colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  options: const LinkifyOptions(humanize: false),
                  linkifiers: const [
                    EmailLinkifier(),
                    UrlLinkifier(),
                    PhoneNumberLinkifier(),
                  ],
                ),
              const SizedBox(height: 4),
              if (!isMediaOnly)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe
                            ? colorScheme.onPrimary.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.deliveryStatus == 'failed'
                            ? Icons.error
                            : message.deliveryStatus == 'pending'
                            ? Icons.schedule
                            : Icons.done_all,
                        size: 12,
                        color: message.deliveryStatus == 'failed'
                            ? Colors.red
                            : colorScheme.onPrimary.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBubble(GroupMessage message, bool isMe) {
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final data = jsonDecode(message.metadata!);
      final lat = data['lat'];
      final lng = data['lng'];
      return GestureDetector(
        onTap: () async {
          final url = Uri.parse('https://maps.google.com/?q=$lat,$lng');
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
          }
        },
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMe
                ? colorScheme.onPrimary.withValues(alpha: 0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.map, size: 40, color: Colors.blue),
              const SizedBox(height: 8),
              Text(
                message.content,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMe ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
              Text(
                'Tap to open map',
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? colorScheme.onPrimary.withOpacity(0.8)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return Text(
        'Invalid location data',
        style: TextStyle(color: colorScheme.error),
      );
    }
  }

  Widget _buildContactBubble(GroupMessage message, bool isMe) {
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final data = jsonDecode(message.metadata!);
      final name = data['name'] ?? 'Unknown';
      final phone = data['phone'] ?? '';
      return Container(
        width: 200,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe
              ? colorScheme.onPrimary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMe
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (phone.isNotEmpty)
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe
                            ? colorScheme.onPrimary.withOpacity(0.8)
                            : colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return Text(
        'Invalid contact data',
        style: TextStyle(color: colorScheme.error),
      );
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMessageInput() {
    final myMember = _group.members.firstWhere(
      (m) => m.userId == AuthService.currentUser?.id,
      orElse: () => GroupMember(
        userId: AuthService.currentUser?.id ?? 0,
        firstName: '',
        lastName: '',
        email: '',
        role: 'MEMBER',
        status: 'PENDING',
      ),
    );

    if (myMember.status != 'APPROVED') {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Text('Your membership is pending approval.'),
        ),
      );
    }

    if (_group.adminOnlyMessage && myMember.role != 'ADMIN') {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Text('Only admins can send messages in this group.'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      prefixIcon: IconButton(
                        icon: Icon(
                          _isEmojiPickerVisible
                              ? Icons.keyboard
                              : Icons.emoji_emotions_outlined,
                          color: Colors.grey[600],
                        ),
                        onPressed: () {
                          setState(() {
                            _isEmojiPickerVisible = !_isEmojiPickerVisible;
                            if (_isEmojiPickerVisible) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          });
                        },
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey[600],
                        ),
                        onPressed: _showAttachmentOptions,
                      ),
                      hintText: 'Message ${_group.name}...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
            if (_isEmojiPickerVisible)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: _messageController,
                  config: Config(
                    height: 250,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      emojiSizeMax:
                          32 *
                          (foundation.defaultTargetPlatform ==
                                  TargetPlatform.iOS
                              ? 1.30
                              : 1.0),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      buttonIconColor: Colors.grey,
                      buttonColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
