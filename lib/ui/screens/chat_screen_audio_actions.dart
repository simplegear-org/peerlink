import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';

class ChatScreenAudioActions {
  final AudioRecorder _audioRecorder;

  Timer? _recordingTimer;
  bool isRecordingVoice = false;
  String? recordingPath;
  String? stoppedRecordingPath;
  Duration recordingDuration = Duration.zero;

  ChatScreenAudioActions({AudioRecorder? audioRecorder})
    : _audioRecorder = audioRecorder ?? AudioRecorder();

  bool get hasStoppedRecording => stoppedRecordingPath != null;

  Future<void> handleVoicePressed({
    required BuildContext context,
    required bool Function() isMounted,
    required VoidCallback refresh,
  }) async {
    if (isRecordingVoice) {
      await stopVoiceRecording(
        context: context,
        isMounted: isMounted,
        refresh: refresh,
      );
      return;
    }
    await startVoiceRecording(
      context: context,
      isMounted: isMounted,
      refresh: refresh,
    );
  }

  Future<void> startVoiceRecording({
    required BuildContext context,
    required bool Function() isMounted,
    required VoidCallback refresh,
  }) async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!isMounted() || !context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.strings.noMicAccess)));
        return;
      }

      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isMounted() || !isRecordingVoice) {
          return;
        }
        recordingDuration += const Duration(seconds: 1);
        refresh();
      });

      isRecordingVoice = true;
      recordingPath = path;
      recordingDuration = Duration.zero;
      if (isMounted()) {
        refresh();
      }
    } catch (error) {
      if (!isMounted() || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.startRecordError(error))),
      );
    }
  }

  Future<void> stopVoiceRecording({
    required BuildContext context,
    required bool Function() isMounted,
    required VoidCallback refresh,
  }) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final stoppedPath = await _audioRecorder.stop();
      final recordedPath = stoppedPath ?? recordingPath;

      isRecordingVoice = false;
      recordingPath = null;
      stoppedRecordingPath = recordedPath;
      if (isMounted()) {
        refresh();
      }

      if (recordedPath == null || recordedPath.isEmpty) {
        return;
      }

      final file = File(recordedPath);
      if (!await file.exists()) {
        return;
      }

      final size = await file.length();
      if (size > 0) {
        return;
      }

      try {
        await file.delete();
      } catch (_) {
        // Ignore cleanup failure for empty recording.
      }
      stoppedRecordingPath = null;
      if (isMounted()) {
        refresh();
      }
    } catch (error) {
      isRecordingVoice = false;
      recordingPath = null;
      stoppedRecordingPath = null;
      if (isMounted() && context.mounted) {
        refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.stopRecordError(error))),
        );
      }
    } finally {
      recordingDuration = Duration.zero;
      if (isMounted()) {
        refresh();
      }
    }
  }

  Future<bool> sendVoiceRecording({
    required BuildContext context,
    required bool Function() isMounted,
    required VoidCallback refresh,
    required ChatController controller,
    required String peerId,
    required Message? replyTo,
    required VoidCallback clearReplyTarget,
    required VoidCallback jumpToBottom,
  }) async {
    final recordedPath = stoppedRecordingPath;
    if (recordedPath == null || recordedPath.isEmpty) {
      return false;
    }

    final file = File(recordedPath);
    if (!await file.exists()) {
      stoppedRecordingPath = null;
      if (isMounted()) {
        refresh();
      }
      return false;
    }

    try {
      final size = await file.length();
      final fileName = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await controller.sendFile(
        peerId,
        fileName: fileName,
        filePath: recordedPath,
        fileSizeBytes: size,
        mimeType: 'audio/mp4',
        replyTo: replyTo,
      );

      stoppedRecordingPath = null;
      if (isMounted()) {
        refresh();
      }
      clearReplyTarget();
      jumpToBottom();
      return true;
    } catch (error) {
      if (!isMounted() || !context.mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.sendVoiceError(error))),
      );
      return false;
    }
  }

  Future<void> dispose() async {
    _recordingTimer?.cancel();
    await _audioRecorder.dispose();
  }
}
