import 'dart:io';

import 'package:flutter/services.dart';

import '../calls/call_log_entry.dart';

class AndroidCallLogService {
  static const MethodChannel _channel = MethodChannel(
    'peerlink/android_call_log/methods',
  );

  const AndroidCallLogService();

  Future<bool> record(CallLogEntry entry) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('recordCall', <String, Object?>{
            'peerId': entry.peerId,
            'contactName': entry.contactName,
            'direction': entry.direction.name,
            'status': entry.status.name,
            'startedAtMs': entry.startedAt.millisecondsSinceEpoch,
            'durationSeconds': entry.durationSeconds,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
