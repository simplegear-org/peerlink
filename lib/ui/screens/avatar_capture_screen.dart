import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../localization/app_strings.dart';

class AvatarCaptureScreen extends StatefulWidget {
  const AvatarCaptureScreen({super.key});

  @override
  State<AvatarCaptureScreen> createState() => _AvatarCaptureScreenState();
}

class _AvatarCaptureScreenState extends State<AvatarCaptureScreen> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _stream;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  bool _cameraError = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _renderer.initialize();
      _stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'facingMode': 'user',
          'width': 640,
          'height': 640,
        },
      });
      _renderer.srcObject = _stream;
    } catch (error) {
      _error = '$error';
      _cameraError = true;
    } finally {
      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_capturing) {
      return;
    }
    final stream = _stream;
    if (stream == null) {
      return;
    }
    final track = stream.getVideoTracks().isNotEmpty
        ? stream.getVideoTracks().first
        : null;
    if (track == null) {
      return;
    }

    setState(() {
      _capturing = true;
    });

    try {
      final frameBuffer = await track.captureFrame();
      final bytes = frameBuffer.asUint8List();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _cameraError = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final tracks = _stream?.getTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }
    _stream?.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.avatarSnapshot)),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _cameraError
                      ? strings.frontCameraOpenError(_error!)
                      : strings.captureError(_error!),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: RTCVideoView(
                        _renderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _capturing ? null : _capture,
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _capturing ? strings.saving : strings.takeSnapshot,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
