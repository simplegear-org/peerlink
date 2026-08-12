import 'package:flutter/services.dart';

class MediaGalleryService {
  static const MethodChannel _channel = MethodChannel(
    'peerlink/media_gallery/methods',
  );

  const MediaGalleryService();

  Future<void> saveMediaIfMissing({
    required String filePath,
    required String fileName,
  }) async {
    await _channel.invokeMethod<void>('saveMediaIfMissing', {
      'filePath': filePath,
      'fileName': fileName,
    });
  }
}
