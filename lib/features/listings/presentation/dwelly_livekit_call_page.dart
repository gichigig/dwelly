import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:realestate/core/services/chat_service.dart';
import 'package:realestate/core/services/livekit_call_service.dart';

class DwellyLivekitCallPage extends StatefulWidget {
  final String roomName;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool isVideo;
  final int? conversationId;

  const DwellyLivekitCallPage({
    super.key,
    required this.roomName,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.isVideo,
    this.conversationId,
  });

  @override
  State<DwellyLivekitCallPage> createState() => _DwellyLivekitCallPageState();
}

class _DwellyLivekitCallPageState extends State<DwellyLivekitCallPage>
    with SingleTickerProviderStateMixin {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _isConnecting = true;
  bool _isMicMuted = false;
  late bool _isCameraOff;
  bool _isSpeakerOn = true;
  String _callStatus = 'Connecting...';

  Timer? _durationTimer;
  Timer? _ringTimeoutTimer;
  int _secondsElapsed = 0;
  static const Duration _ringTimeout = Duration(seconds: 35);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _isCameraOff = !widget.isVideo;
    _isSpeakerOn = widget.isVideo;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startConnection();
  }

  void _startRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(_ringTimeout, () {
      if (!mounted) return;
      if (_secondsElapsed == 0 && (_room == null || _room!.remoteParticipants.isEmpty)) {
        setState(() {
          _isConnecting = false;
          _callStatus = 'No answer';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.otherUserName} did not answer'),
              backgroundColor: Colors.orangeAccent,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _endCall();
          }
        });
      }
    });
  }

  Future<void> _startConnection() async {
    _startRingTimeout();
    try {
      final creds = await LivekitCallService.instance.fetchCredentials(
        roomName: widget.roomName,
        isVideo: widget.isVideo,
      ).timeout(const Duration(seconds: 15));

      final room = await LivekitCallService.instance.connectToRoom(
        url: creds.wsUrl,
        token: creds.token,
        isVideo: widget.isVideo,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      _room = room;
      _listener = room.createListener();
      _setUpListeners();

      if (room.remoteParticipants.isNotEmpty) {
        _ringTimeoutTimer?.cancel();
        setState(() {
          _isConnecting = false;
          _callStatus = 'Connected';
        });
        _startTimer();
      } else {
        setState(() {
          _isConnecting = false;
          _callStatus = 'Waiting for ${widget.otherUserName}...';
        });
      }
    } catch (e) {
      _ringTimeoutTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _callStatus = 'Call timed out or failed';
      });
      // Show snackbar error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not connect call: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _endCall();
        }
      });
    }
  }

  void _setUpListeners() {
    _listener
      ?..on<RoomEvent>((event) {
        if (!mounted) return;
        setState(() {});
      })
      ..on<ParticipantConnectedEvent>((event) {
        if (!mounted) return;
        _ringTimeoutTimer?.cancel();
        setState(() {
          _callStatus = 'Connected';
        });
        _startTimer();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (!mounted) return;
        if (_room == null || _room!.remoteParticipants.isEmpty) {
          _endCall();
        }
      })
      ..on<RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        _endCall();
      });
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _toggleMic() async {
    final next = !_isMicMuted;
    await LivekitCallService.instance.setMicrophoneEnabled(!next);
    setState(() {
      _isMicMuted = next;
    });
  }

  Future<void> _toggleCamera() async {
    final next = !_isCameraOff;
    await LivekitCallService.instance.setCameraEnabled(!next);
    setState(() {
      _isCameraOff = next;
    });
  }

  Future<void> _flipCamera() async {
    await LivekitCallService.instance.flipCamera();
  }

  Future<void> _toggleSpeaker() async {
    final next = !_isSpeakerOn;
    await LivekitCallService.instance.setSpeakerphoneOn(next);
    setState(() {
      _isSpeakerOn = next;
    });
  }

  Future<void> _endCall() async {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();

    // If call ended before remote participant joined/answered, send CALL_CANCEL signal to recipient
    if (_secondsElapsed == 0 && (_room == null || _room!.remoteParticipants.isEmpty) && widget.conversationId != null) {
      try {
        final cancelJson = jsonEncode({
          'roomName': widget.roomName,
          'type': 'CALL_CANCEL',
          'conversationId': widget.conversationId,
        });
        unawaited(
          ChatService.sendMessage(
            conversationId: widget.conversationId!,
            content: cancelJson,
            messageType: 'CALL_CANCEL',
          ),
        );
      } catch (e) {
        debugPrint('Failed to send call cancel signal: $e');
      }
    }

    await LivekitCallService.instance.disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  VideoTrack? _getRemoteVideoTrack() {
    final remoteParticipants = _room?.remoteParticipants.values;
    if (remoteParticipants != null && remoteParticipants.isNotEmpty) {
      for (final p in remoteParticipants) {
        for (final pub in p.videoTrackPublications) {
          if (!pub.muted && pub.track is VideoTrack) {
            return pub.track as VideoTrack;
          }
        }
      }
    }
    return null;
  }

  VideoTrack? _getLocalVideoTrack() {
    final localParticipant = _room?.localParticipant;
    if (localParticipant != null) {
      for (final pub in localParticipant.videoTrackPublications) {
        if (!pub.muted && pub.track is VideoTrack) {
          return pub.track as VideoTrack;
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideoTrack = _getRemoteVideoTrack();
    final localVideoTrack = _getLocalVideoTrack();
    final hasRemoteVideo = remoteVideoTrack != null;
    final hasLocalVideo = localVideoTrack != null && !_isCameraOff;

    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      body: Stack(
        children: [
          // Background Video or Avatar Stage
          Positioned.fill(
            child: _buildMainStage(hasRemoteVideo, remoteVideoTrack, hasLocalVideo, localVideoTrack),
          ),

          // Top Header Bar (Glassmorphic)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.otherUserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              color: Colors.greenAccent,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _secondsElapsed > 0
                                    ? 'End-to-end Encrypted • ${_formatDuration(_secondsElapsed)}'
                                    : _callStatus,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Picture-In-Picture Local Video (when remote is showing)
          if (hasRemoteVideo && hasLocalVideo)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 70,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(color: Colors.white24, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: VideoTrackRenderer(
                    localVideoTrack,
                    fit: VideoViewFit.cover,
                  ),
                ),
              ),
            ),

          // Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: 24,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlPill(
                    icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                    color: _isMicMuted ? Colors.redAccent : Colors.white24,
                    onTap: _toggleMic,
                  ),
                  if (widget.isVideo) ...[
                    _buildControlPill(
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      color: _isCameraOff ? Colors.redAccent : Colors.white24,
                      onTap: _toggleCamera,
                    ),
                    _buildControlPill(
                      icon: Icons.flip_camera_ios,
                      color: Colors.white24,
                      onTap: _flipCamera,
                    ),
                  ],
                  _buildControlPill(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    color: _isSpeakerOn ? Colors.blueAccent : Colors.white24,
                    onTap: _toggleSpeaker,
                  ),
                  _buildControlPill(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    iconColor: Colors.white,
                    size: 60,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStage(
    bool hasRemoteVideo,
    VideoTrack? remoteVideoTrack,
    bool hasLocalVideo,
    VideoTrack? localVideoTrack,
  ) {
    if (hasRemoteVideo && remoteVideoTrack != null) {
      return VideoTrackRenderer(
        remoteVideoTrack,
        fit: VideoViewFit.cover,
      );
    }

    if (hasLocalVideo && localVideoTrack != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          VideoTrackRenderer(
            localVideoTrack,
            fit: VideoViewFit.cover,
          ),
          Container(color: Colors.black.withOpacity(0.4)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  'Waiting for ${widget.otherUserName} to join...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Audio Call or Video Waiting Stage
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _isConnecting ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                    Theme.of(context).colorScheme.secondary.withOpacity(0.8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.otherUserName.isNotEmpty
                      ? widget.otherUserName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.otherUserName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _secondsElapsed > 0 ? _formatDuration(_secondsElapsed) : _callStatus,
            style: TextStyle(
              color: _secondsElapsed > 0 ? Colors.greenAccent : Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPill({
    required IconData icon,
    required Color color,
    Color iconColor = Colors.white,
    double size = 52,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.45),
      ),
    );
  }
}
