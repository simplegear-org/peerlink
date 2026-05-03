import 'dart:async';

import 'package:flutter/services.dart';

class DeepLinkService {
  static const DeepLinkService instance = DeepLinkService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'peerlink/deep_links/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'peerlink/deep_links/events',
  );

  const DeepLinkService._();

  Future<String?> initialLink() async {
    try {
      return await _methodChannel.invokeMethod<String>('getInitialLink');
    } on MissingPluginException {
      return null;
    }
  }

  Stream<String> get links {
    return _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is String)
        .cast<String>();
  }
}
