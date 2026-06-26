import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_page.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/contact_match.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/group_service.dart';
import '../../../core/widgets/create_group_dialog.dart';
import 'group_chat_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ContactsListPage extends StatefulWidget {
  final bool initialSelectionMode;
  const ContactsListPage({super.key, this.initialSelectionMode = false});

  @override
  State<ContactsListPage> createState() => _ContactsListPageState();
}

class _ContactsListPageState extends State<ContactsListPage> {
  bool _isLoading = true;
  String? _error;

  List<ContactMatch> _dwellyMatches = [];
  List<Contact> _dwellyContacts = [];
  List<Contact> _inviteContacts = [];

  // For multi-select "New Group" mode
  bool _isSelectionMode = false;
  Set<int> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    _isSelectionMode = widget.initialSelectionMode;
    _loadAndSyncContacts();
  }

  Future<void> _loadAndSyncContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (!await Permission.contacts.request().isGranted) {
        setState(() {
          _error = 'Permission to read contacts was denied.';
          _isLoading = false;
        });
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email},
      );

      final identifiers = <String>{};
      final identifierToContact = <String, Contact>{};

      for (var contact in contacts) {
        for (var phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          identifiers.add(normalized);
          identifierToContact[normalized] = contact;
        }
        for (var email in contact.emails) {
          final normalized = email.address.trim().toLowerCase();
          identifiers.add(normalized);
          identifierToContact[normalized] = contact;
        }
      }

      if (identifiers.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/contacts/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'identifiers': identifiers.toList()}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final matches = data.map((json) => ContactMatch.fromJson(json)).toList();

        final dwellyMatchedIdentifiers = <String>{};
        final dwellyContactsSet = <Contact>{};
        final dwellyMatchesFiltered = <ContactMatch>[];

        for (var match in matches) {
          if (match.matchedIdentifier != null) {
            dwellyMatchedIdentifiers.add(match.matchedIdentifier!);
            final contact = identifierToContact[match.matchedIdentifier!];
            if (contact != null) {
              if (!dwellyContactsSet.contains(contact)) {
                dwellyContactsSet.add(contact);
                dwellyMatchesFiltered.add(match);
              }
            }
          }
        }

        final inviteSet = <Contact>{};
        for (var contact in contacts) {
          if (!dwellyContactsSet.contains(contact) && contact.phones.isNotEmpty) {
            inviteSet.add(contact);
          }
        }

        setState(() {
          _dwellyMatches = dwellyMatchesFiltered;
          _dwellyContacts = dwellyContactsSet.toList();
          _inviteContacts = inviteSet.toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to sync contacts. Server returned ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error syncing contacts: $e';
        _isLoading = false;
      });
    }
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _startChat(ContactMatch match) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      final conversation = await ChatService.startConversation(
        targetUserId: match.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      Navigator.of(context).pop(); // pop contacts page
      final pseudoRental = Rental(
        id: conversation.rentalId ?? 0,
        ownerId: conversation.ownerId,
        title: conversation.listingTitle ?? 'Chat',
        description: conversation.lastMessage ?? '',
        price: 0,
        address: conversation.listingTitle ?? 'Direct Message',
        city: '',
        state: '',
        bedrooms: 0,
        bathrooms: 0,
        squareFeet: 0,
        propertyType: 'OTHER',
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            rental: pseudoRental,
            existingConversation: conversation,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start chat: $e')),
      );
    }
  }

  Future<void> _inviteContact(Contact contact) async {
    if (contact.phones.isEmpty) return;
    
    // Grab the first phone number
    final phoneRaw = contact.phones.first.number;
    final phone = _normalizePhone(phoneRaw);
    final message = Uri.encodeComponent("Hey! I'm using Dwelly to find and manage rentals. Join me here: https://dwelly.com");

    final whatsappUrl = Uri.parse("whatsapp://send?phone=$phone&text=$message");
    final smsUrl = Uri.parse("sms:$phone?body=$message");

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl);
      } else {
        // Fallback to SMS
        if (await canLaunchUrl(smsUrl)) {
          await launchUrl(smsUrl);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open WhatsApp or Messages app.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch invite app.')),
        );
      }
    }
  }

  void _toggleSelection(int userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _createGroup() async {
    if (_selectedUserIds.isEmpty) return;

    if (widget.initialSelectionMode) {
      Navigator.pop(context, _selectedUserIds.toList());
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreateGroupDialog(),
    );

    if (result == null || result['name'] == null || (result['name'] as String).isEmpty) return;

    final name = result['name'] as String;
    final buildingId = result['buildingId'] as int?;

    setState(() {
      _isLoading = true;
    });

    try {
      final newGroup = await GroupService.createGroup(name, buildingId: buildingId);
      
      for (final userId in _selectedUserIds) {
        if (userId == AuthService.currentUser?.id) continue;
        try {
          await GroupService.addMember(newGroup.id, userId.toString());
        } catch (e) {
          debugPrint('Failed to add member $userId: $e');
        }
      }
      
      if (!mounted) return;
      Navigator.pop(context); // Pop contacts list page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatPage(group: newGroup),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
      setState(() {
        _isLoading = false;
        _isSelectionMode = false;
        _selectedUserIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode 
            ? '${_selectedUserIds.length} selected' 
            : (widget.initialSelectionMode ? 'Select Members' : 'New Chat')),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  if (widget.initialSelectionMode) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedUserIds.clear();
                    });
                  }
                },
              )
            : null,
        actions: [
          if (!_isLoading && _error == null && _dwellyMatches.isNotEmpty)
            if (_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _selectedUserIds.isNotEmpty ? _createGroup : null,
              )
            else
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
                child: const Text('New Group'),
              ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadAndSyncContacts,
                child: const Text('Try Again'),
              )
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (_dwellyMatches.isNotEmpty) ...[
          _buildSectionHeader('Contacts on Dwelly'),
          ..._dwellyMatches.asMap().entries.map((entry) {
            final index = entry.key;
            final match = entry.value;
            final localContact = _dwellyContacts[index];

            return _buildDwellyContactItem(localContact, match);
          }),
        ],
        if (_inviteContacts.isNotEmpty) ...[
          _buildSectionHeader('Invite to Dwelly'),
          ..._inviteContacts.map((contact) {
            return _buildInviteContactItem(contact);
          }),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDwellyContactItem(Contact localContact, ContactMatch match) {
    final displayNameText = localContact.displayName;
    final name = (displayNameText != null && displayNameText.isNotEmpty) 
        ? displayNameText 
        : '${match.firstName ?? ''} ${match.lastName ?? ''}'.trim();
    
    final isMe = match.userId == AuthService.currentUser?.id;
    final displayName = name.isNotEmpty ? name : (match.username ?? 'Unknown');
    final finalName = isMe ? '$displayName (You)' : displayName;
    final initial = finalName.isNotEmpty ? finalName[0].toUpperCase() : '?';

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: match.avatarUrl != null && match.avatarUrl!.isNotEmpty
                ? CachedNetworkImageProvider(ApiService.resolveMediaUrl(match.avatarUrl!)!) as ImageProvider
                : null,
            child: match.avatarUrl == null || match.avatarUrl!.isEmpty
                ? Text(
                    initial,
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                  )
                : null,
          ),
          if (_isSelectionMode)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Icon(
                  _selectedUserIds.contains(match.userId)
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 20,
                  color: _selectedUserIds.contains(match.userId)
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
            ),
        ],
      ),
      title: Text(finalName),
      subtitle: Text(match.username != null ? '@${match.username}' : 'Dwelly User'),
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(match.userId);
        } else {
          _startChat(match);
        }
      },
    );
  }

  Widget _buildInviteContactItem(Contact contact) {
    final displayNameText = contact.displayName;
    final name = (displayNameText != null && displayNameText.isNotEmpty) ? displayNameText : 'Unknown Contact';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        child: Text(
          initial,
          style: TextStyle(color: Colors.grey[800]),
        ),
      ),
      title: Text(name),
      subtitle: Text(phone),
      trailing: TextButton(
        onPressed: () => _inviteContact(contact),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
        ),
        child: const Text('Invite'),
      ),
      onTap: () => _inviteContact(contact),
    );
  }
}
