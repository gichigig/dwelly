import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:realestate/core/services/api_service.dart';
import 'package:realestate/core/services/auth_service.dart';

class CallCredentials {
  final String token;
  final String wsUrl;

  const CallCredentials({required this.token, required this.wsUrl});
}

class LivekitCallService {
  static final LivekitCallService instance = LivekitCallService._internal();
  LivekitCallService._internal();

  Room? currentRoom;
  EventsListener<RoomEvent>? roomListener;

  /// Fetch LiveKit access token and WebSocket URL from backend
  Future<CallCredentials> fetchCredentials({
    required String roomName,
    required bool isVideo,
  }) async {
    final user = AuthService.currentUser;
    final participantName = user?.fullName ?? user?.username ?? 'User';

    try {
      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/chat/call/token'),
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode({
          'roomName': roomName,
          'participantName': participantName,
          'isVideo': isVideo,
        }),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body);
        final token = data['token']?.toString() ?? '';
        final wsUrl = data['livekitUrl']?.toString() ??
            data['wsUrl']?.toString() ??
            'wss://livekit.ishinadwelly.com';
        if (token.isNotEmpty) {
          return CallCredentials(token: token, wsUrl: wsUrl);
        }
      }
    } catch (e) {
      debugPrint('Error fetching LiveKit token from backend: $e');
    }

    // Fallback URL if backend endpoint is still deploying or not configured yet
    const defaultWsUrl = 'wss://livekit.ishinadwelly.com';
    return const CallCredentials(
      token: '', // When testing without token server, connection error will prompt user or use test token
      wsUrl: defaultWsUrl,
    );
  }

  /// Connect to a LiveKit room
  Future<Room> connectToRoom({
    required String url,
    required String token,
    required bool isVideo,
  }) async {
    // Request microphone & camera permissions
    await Permission.microphone.request();
    if (isVideo) {
      await Permission.camera.request();
    }

    // Clean up any existing connection
    await disconnect();

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );

    currentRoom = room;
    roomListener = room.createListener();

    try {
      await room.connect(
        url,
        token,
        connectOptions: const ConnectOptions(),
      ).timeout(const Duration(seconds: 15));

      // Enable local tracks based on call type
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (isVideo) {
        await room.localParticipant?.setCameraEnabled(true);
      }

      try {
        await Hardware.instance.setSpeakerphoneOn(isVideo);
      } catch (e) {
        debugPrint('Could not set speakerphone: $e');
      }

      return room;
    } catch (e) {
      debugPrint('LiveKit connection error: $e');
      await disconnect();
      rethrow;
    }
  }

  /// Disconnect and dispose room
  Future<void> disconnect() async {
    try {
      await roomListener?.dispose();
      roomListener = null;

      if (currentRoom != null) {
        await currentRoom!.disconnect();
        await currentRoom!.dispose();
        currentRoom = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting room: $e');
    }
  }

  /// Mute or unmute local microphone
  Future<void> setMicrophoneEnabled(bool enabled) async {
    try {
      await currentRoom?.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (e) {
      debugPrint('Error toggling microphone: $e');
    }
  }

  /// Turn on or off local camera
  Future<void> setCameraEnabled(bool enabled) async {
    try {
      await currentRoom?.localParticipant?.setCameraEnabled(enabled);
    } catch (e) {
      debugPrint('Error toggling camera: $e');
    }
  }

  /// Switch between front and back camera
  Future<void> flipCamera() async {
    try {
      final videoPublications = currentRoom?.localParticipant?.videoTrackPublications;
      if (videoPublications != null && videoPublications.isNotEmpty) {
        final track = videoPublications.first.track;
        if (track is LocalVideoTrack) {
          // Switch camera on the active video track
          final options = track.currentOptions;
          if (options is CameraCaptureOptions) {
            final newPosition = options.cameraPosition == CameraPosition.front
                ? CameraPosition.back
                : CameraPosition.front;
            await track.setCameraPosition(newPosition);
          }
        }
      }
    } catch (e) {
      debugPrint('Error flipping camera: $e');
    }
  }

  /// Toggle speakerphone
  Future<void> setSpeakerphoneOn(bool enabled) async {
    try {
      await Hardware.instance.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('Error toggling speakerphone: $e');
    }
  }
}
