import 'package:flutter/material.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/models/chat.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';

class MutedBlockedContactsPage extends StatefulWidget {
  const MutedBlockedContactsPage({super.key});

  @override
  State<MutedBlockedContactsPage> createState() =>
      _MutedBlockedContactsPageState();
}

class _MutedBlockedContactsPageState extends State<MutedBlockedContactsPage> {
  ChatSafetyFilterMode _mode = ChatSafetyFilterMode.all;
  bool _isLoading = true;
  String? _error;
  List<ChatSafetyContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _contacts = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ChatService.getSafetyContacts(mode: _mode);
      if (!mounted) return;
      setState(() {
        _contacts = result.contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load muted/blocked contacts.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _setMute(ChatSafetyContact contact, bool muted) async {
    try {
      await ChatService.updateContactSafety(contact.targetUserId, muted: muted);
      await _loadContacts();
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to update mute settings.',
      );
    }
  }

  Future<void> _setBlock(ChatSafetyContact contact, bool blocked) async {
    if (blocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block contact?'),
          content: const Text(
            'Blocking prevents both of you from sending messages to each other.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ChatService.updateContactSafety(
        contact.targetUserId,
        blocked: blocked,
      );
      ChatService.invalidateListingVisibilityCaches();
      await _loadContacts();
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to update block settings.',
      );
    }
  }

  Future<void> _clear(ChatSafetyContact contact) async {
    try {
      await ChatService.clearContactSafety(contact.targetUserId);
      ChatService.invalidateListingVisibilityCaches();
      await _loadContacts();
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to clear contact settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Muted/Blocked Contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SegmentedButton<ChatSafetyFilterMode>(
              segments: const [
                ButtonSegment(
                  value: ChatSafetyFilterMode.all,
                  label: Text('All'),
                ),
                ButtonSegment(
                  value: ChatSafetyFilterMode.muted,
                  label: Text('Muted'),
                ),
                ButtonSegment(
                  value: ChatSafetyFilterMode.blocked,
                  label: Text('Blocked'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                });
                _loadContacts();
              },
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sign in to manage muted and blocked contacts.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => showLoginBottomSheet(
                  context,
                  onSuccess: () {
                    _loadContacts();
                  },
                ),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadContacts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_contacts.isEmpty) {
      return const Center(child: Text('No contacts in this list.'));
    }

    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView.separated(
        itemCount: _contacts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                contact.targetName.isEmpty
                    ? '?'
                    : contact.targetName.substring(0, 1).toUpperCase(),
              ),
            ),
            title: Text(contact.targetName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.targetEmail != null &&
                    contact.targetEmail!.isNotEmpty)
                  Text(contact.targetEmail!),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (contact.muted)
                      Chip(
                        label: const Text('Muted'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (contact.blocked)
                      Chip(
                        label: const Text('Blocked'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'mute':
                    _setMute(contact, true);
                    break;
                  case 'unmute':
                    _setMute(contact, false);
                    break;
                  case 'block':
                    _setBlock(contact, true);
                    break;
                  case 'unblock':
                    _setBlock(contact, false);
                    break;
                  case 'clear':
                    _clear(contact);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: contact.muted ? 'unmute' : 'mute',
                  child: Text(contact.muted ? 'Unmute notifications' : 'Mute'),
                ),
                PopupMenuItem(
                  value: contact.blocked ? 'unblock' : 'block',
                  child: Text(contact.blocked ? 'Unblock' : 'Block'),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear settings'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
