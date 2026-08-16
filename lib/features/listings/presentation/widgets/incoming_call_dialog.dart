import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/chat_service.dart';
import 'package:realestate/features/listings/models/call_invite_model.dart';
import 'package:realestate/features/listings/presentation/dwelly_livekit_call_page.dart';

class IncomingCallDialog extends StatefulWidget {
  final CallInviteModel invite;

  const IncomingCallDialog({
    super.key,
    required this.invite,
  });

  static BuildContext? _activeContext;
  static String? _activeRoomName;
  static bool _isOpen = false;

  static Future<void> show(BuildContext context, CallInviteModel invite) async {
    dismissIfOpen(context);
    _isOpen = true;
    _activeContext = context;
    _activeRoomName = invite.roomName;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => IncomingCallDialog(invite: invite),
      );
    } finally {
      _isOpen = false;
      _activeContext = null;
      _activeRoomName = null;
    }
  }

  static void dismissIfOpen(BuildContext context, {String? roomName}) {
    if (_isOpen && _activeContext != null) {
      if (roomName != null && _activeRoomName != null && roomName != _activeRoomName) {
        return;
      }
      try {
        Navigator.of(_activeContext!).pop();
      } catch (_) {}
      _isOpen = false;
      _activeContext = null;
      _activeRoomName = null;
    }
  }

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _autoDismissTimer;

  static const int _ringTimeoutSeconds = 30;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Automatically dismiss incoming call dialog after timeout if not answered
    _autoDismissTimer = Timer(const Duration(seconds: _ringTimeoutSeconds), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _acceptCall() {
    _autoDismissTimer?.cancel();
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DwellyLivekitCallPage(
          roomName: widget.invite.roomName,
          otherUserName: widget.invite.callerName,
          otherUserAvatar: widget.invite.callerAvatar,
          isVideo: widget.invite.isVideo,
          conversationId: widget.invite.conversationId,
        ),
      ),
    );
  }

  void _declineCall() {
    _autoDismissTimer?.cancel();
    if (widget.invite.conversationId != null) {
      try {
        final rejectJson = jsonEncode({
          'roomName': widget.invite.roomName,
          'type': 'CALL_REJECT',
          'conversationId': widget.invite.conversationId,
        });
        unawaited(
          ChatService.sendMessage(
            conversationId: widget.invite.conversationId!,
            content: rejectJson,
            messageType: 'CALL_REJECT',
          ),
        );
      } catch (_) {}
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.invite.isVideo;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white12, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam : Icons.call,
                  color: Colors.greenAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'INCOMING ${isVideo ? "VIDEO" : "VOICE"} CALL',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.8),
                      colorScheme.secondary.withOpacity(0.8),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    widget.invite.callerName.isNotEmpty
                        ? widget.invite.callerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.invite.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'IshinaDwelly Encrypted Audio/Video',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline Button
                _buildActionBtn(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: Colors.redAccent,
                  onTap: _declineCall,
                ),
                const SizedBox(width: 32),
                // Accept Button
                _buildActionBtn(
                  icon: isVideo ? Icons.videocam : Icons.call,
                  label: 'Accept',
                  color: Colors.green.shade600,
                  onTap: _acceptCall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
