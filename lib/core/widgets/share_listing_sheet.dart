import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/rental.dart';
import '../models/chat.dart';
import '../models/contact_match.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/listing_share_service.dart';
import '../services/api_service.dart';
import 'auth_bottom_sheets.dart';
import '../../features/listings/presentation/contacts_list_page.dart';
import '../../features/helper/presentation/helper_hub_page.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class ShareListingSheet extends StatelessWidget {
  final Rental rental;

  const ShareListingSheet({super.key, required this.rental});

  static Future<void> show(BuildContext context, Rental rental) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ShareListingSheet(rental: rental),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share Listing',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),

            // Listing Preview Mini Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: rental.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: rental.imageUrls.first.startsWith('http')
                                ? rental.imageUrls.first
                                : '${ApiService.effectiveBaseUrl.replaceAll('/api', '')}${rental.imageUrls.first}',
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey[300]),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.home,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey[800],
                            child: const Icon(Icons.home, color: Colors.white),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rental.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rental.formattedPrice,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rental.fullAddress.isNotEmpty
                              ? rental.fullAddress
                              : rental.city,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Real Social Media Share Options Grid/List
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ShareOptionButton(
                    icon: Icons.copy_rounded,
                    color: Colors.blue,
                    label: 'Copy Link',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.copyShareLink(context, rental);
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: FontAwesomeIcons.whatsapp,
                    color: const Color(0xFF25D366),
                    label: 'WhatsApp',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.shareViaWhatsApp(
                        context,
                        rental,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: FontAwesomeIcons.telegram,
                    color: const Color(0xFF0088CC),
                    label: 'Telegram',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.shareViaTelegram(
                        context,
                        rental,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: FontAwesomeIcons.facebook,
                    color: const Color(0xFF1877F2),
                    label: 'Facebook',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.shareViaFacebook(
                        context,
                        rental,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: FontAwesomeIcons.xTwitter,
                    color: const Color(0xFF1DA1F2),
                    label: 'X / Twitter',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.shareViaTwitter(
                        context,
                        rental,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: Icons.sms_rounded,
                    color: Colors.orange,
                    label: 'SMS',
                    onTap: () async {
                      Navigator.pop(context);
                      await ListingShareService.shareViaSms(context, rental);
                    },
                  ),
                  const SizedBox(width: 8),
                  _ShareOptionButton(
                    icon: Icons.share_rounded,
                    color: Colors.purple,
                    label: 'More...',
                    onTap: () async {
                      final box = context.findRenderObject() as RenderBox?;
                      final origin = box != null
                          ? box.localToGlobal(Offset.zero) & box.size
                          : null;
                      await ListingShareService.shareViaSystem(
                        context,
                        rental,
                        sharePositionOrigin: origin,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),

            // In-App Chat Share
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.send_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: const Text(
                'Send inside Dwelly Chat',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Share directly to a contact or conversation as a rich card',
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                Navigator.pop(context);
                if (!AuthService.isLoggedIn) {
                  showSignupBottomSheet(
                    context,
                    onSuccess: () => _showConversationPicker(context, rental),
                  );
                  return;
                }
                _showConversationPicker(context, rental);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationPicker(BuildContext context, Rental rental) {
    showDialog(
      context: context,
      builder: (ctx) => _ConversationPickerDialog(rental: rental),
    );
  }
}

class _ShareOptionButton extends StatelessWidget {
  final dynamic icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareOptionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: color.withValues(alpha: 0.15),
              child: icon is IconData
                  ? Icon(icon, color: color, size: 24)
                  : FaIcon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPickerDialog extends StatefulWidget {
  final Rental rental;

  const _ConversationPickerDialog({required this.rental});

  @override
  State<_ConversationPickerDialog> createState() =>
      _ConversationPickerDialogState();
}

class _ConversationPickerDialogState extends State<_ConversationPickerDialog> {
  List<Conversation> _conversations = [];
  List<ContactMatch> _dwellyMatches = [];
  bool _loading = true;
  int? _sendingToId;

  @override
  void initState() {
    super.initState();
    _loadConversationsAndContacts();
  }

  Future<void> _loadConversationsAndContacts() async {
    try {
      final list = await ChatService.getConversations();
      List<ContactMatch> matches = [];
      try {
        if (await Permission.contacts.isGranted) {
          final contacts = await FlutterContacts.getAll(
            properties: {ContactProperty.phone},
          );
          final identifiers = <String>{};
          for (var contact in contacts) {
            for (var phone in contact.phones) {
              final normalized = phone.number.replaceAll(RegExp(r'\D'), '');
              if (normalized.isNotEmpty) {
                identifiers.add(normalized);
              }
            }
          }
          if (identifiers.isNotEmpty) {
            final response = await ApiService.timedPost(
              Uri.parse('${ApiService.baseUrl}/contacts/sync'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${AuthService.token}',
              },
              body: jsonEncode({'identifiers': identifiers.toList()}),
            );
            if (response.statusCode == 200 && mounted) {
              final List<dynamic> data = jsonDecode(response.body);
              matches = data
                  .map((json) => ContactMatch.fromJson(json))
                  .toList();
            }
          }
        }
      } catch (e) {
        debugPrint('Contact sync note in share dialog: $e');
      }

      if (mounted) {
        setState(() {
          _conversations = list;
          _dwellyMatches = matches;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendToListingShare(Conversation conversation) async {
    setState(() => _sendingToId = conversation.id);
    try {
      await ChatService.sendMessageQueued(
        conversationId: conversation.id ?? 0,
        clientMessageId: DateTime.now().millisecondsSinceEpoch.toString(),
        content: jsonEncode({
          'id': widget.rental.id,
          'title': widget.rental.title,
          'price': widget.rental.formattedPrice,
          'location': widget.rental.fullAddress.isNotEmpty
              ? widget.rental.fullAddress
              : widget.rental.city,
          'imageUrl': widget.rental.imageUrls.isNotEmpty
              ? widget.rental.imageUrls.first
              : '',
        }),
        messageType: 'LISTING_SHARE',
        mediaUrl: ListingShareService.getShareUrl(widget.rental),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing shared successfully directly to chat!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingToId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  Future<void> _sendToContactMatch(ContactMatch match) async {
    setState(() => _sendingToId = match.userId);
    try {
      final conv = await ChatService.startConversation(
        targetUserId: match.userId,
      );
      await _sendToListingShare(conv);
    } catch (e) {
      if (mounted) {
        setState(() => _sendingToId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share to contact: $e')),
        );
      }
    }
  }

  void _shareOrOpenHelper() {
    // Check if we already have an active conversation with a Helper
    try {
      final helperConv = _conversations.firstWhere(
        (c) =>
            c.rentalTitle.toLowerCase().contains('helper') ||
            c.listingType == 'HELPER',
      );
      _sendToListingShare(helperConv);
    } catch (_) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HelperHubPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.currentUser?.id ?? 0;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text(
        'Share inside Dwelly',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _loading
            ? const Center(child: DwellyOrbitingLoader())
            : ListView(
                children: [
                  // Quick Actions
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.support_agent_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      'Dwelly Helper Hub',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('Share with helper or support'),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                    ),
                    onTap: _shareOrOpenHelper,
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      child: const Icon(
                        Icons.contacts_rounded,
                        color: Colors.green,
                      ),
                    ),
                    title: const Text(
                      'All Phone Contacts',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('Browse contacts on Dwelly'),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ContactsListPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(),

                  // Active Conversations
                  if (_conversations.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 4.0,
                      ),
                      child: Text(
                        'Active Conversations (${_conversations.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    ..._conversations.map((conv) {
                      final isMeUser = conv.userId == currentUserId;
                      final otherName = isMeUser
                          ? conv.ownerName
                          : conv.userName;
                      final otherAvatar = isMeUser
                          ? conv.ownerAvatarUrl
                          : conv.userAvatarUrl;
                      final isSending = _sendingToId == conv.id;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              otherAvatar != null && otherAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(otherAvatar)
                              : null,
                          child: (otherAvatar == null || otherAvatar.isEmpty)
                              ? Text(
                                  otherName.isNotEmpty
                                      ? otherName[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(
                          otherName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          conv.rentalTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: DwellyOrbitingLoader(),
                              )
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () => _sendToListingShare(conv),
                                child: const Text('Send'),
                              ),
                      );
                    }),
                  ],

                  // Contacts using Dwelly
                  if (_dwellyMatches.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 4.0,
                      ),
                      child: Text(
                        'Contacts on Dwelly (${_dwellyMatches.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    ..._dwellyMatches.map((match) {
                      final isSending = _sendingToId == match.userId;
                      final nameText =
                          (match.firstName ?? '') +
                          (match.lastName != null ? ' ${match.lastName}' : '');
                      final cleanName =
                          nameText.trim().isNotEmpty && !nameText.contains('@')
                          ? nameText.trim()
                          : ((match.username != null &&
                                    !match.username!.contains('@'))
                                ? match.username!
                                : 'Dwelly Contact');
                      final initial = cleanName.isNotEmpty
                          ? cleanName[0].toUpperCase()
                          : '?';

                      final subtitleText =
                          (match.username != null &&
                              !match.username!.contains('@'))
                          ? '@${match.username}'
                          : (match.matchedIdentifier != null &&
                                    !match.matchedIdentifier!.contains('@')
                                ? match.matchedIdentifier!
                                : 'On Dwelly');

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              match.avatarUrl != null &&
                                  match.avatarUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(match.avatarUrl!)
                              : null,
                          child:
                              (match.avatarUrl == null ||
                                  match.avatarUrl!.isEmpty)
                              ? Text(initial)
                              : null,
                        ),
                        title: Text(
                          cleanName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(subtitleText),
                        trailing: isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: DwellyOrbitingLoader(),
                              )
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () => _sendToContactMatch(match),
                                child: const Text('Send'),
                              ),
                      );
                    }),
                  ],

                  if (_conversations.isEmpty && _dwellyMatches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'No recent conversations or contacts found. Use the options above to start sharing!',
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
