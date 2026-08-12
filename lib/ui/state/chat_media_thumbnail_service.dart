import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../core/runtime/diagnostic_log.dart' as diag;
import '../models/message.dart';

class ChatMediaThumbnailService {
  static const String thumbnailSuffix = '-thumb-first-visible-v2.jpg';
  static const int thumbnailWidth = 640;
  static const int thumbnailHeight = 440;
  static const MethodChannel _channel = MethodChannel(
    'peerlink/media_thumbnail/methods',
  );

  const ChatMediaThumbnailService();

  Future<String?> ensureThumbnail(Message message) async {
    final mediaKind = _mediaKind(message);
    if (message.kind != MessageKind.file || mediaKind == null) {
      return null;
    }
    if (mediaKind == _ThumbnailMediaKind.video) {
      _logThumbnailEvent(message, event: 'skip-video');
      return null;
    }
    final existing = message.thumbnailPath?.trim();
    if (existing != null &&
        existing.isNotEmpty &&
        existing.endsWith(thumbnailSuffix)) {
      try {
        if (await File(existing).exists()) {
          _logThumbnailEvent(message, event: 'hit-existing', path: existing);
          return existing;
        }
        _logThumbnailEvent(
          message,
          event: 'stored-path-missing',
          path: existing,
        );
      } catch (_) {
        // Regenerate below.
      }
    }

    final sourcePath = message.localFilePath?.trim();
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }
    final sourceFile = File(sourcePath);
    try {
      if (!await sourceFile.exists()) {
        _logThumbnailEvent(message, event: 'source-missing');
        return null;
      }
    } catch (_) {
      _logThumbnailEvent(message, event: 'source-check-failed');
      return null;
    }

    final destinationPath = _thumbnailPath(
      sourcePath: sourcePath,
      messageId: message.id,
    );
    if (destinationPath == null) {
      return null;
    }
    try {
      final destination = File(destinationPath);
      if (await destination.exists()) {
        _logThumbnailEvent(
          message,
          event: 'hit-destination',
          path: destination.path,
        );
        return destination.path;
      }
    } catch (_) {
      _logThumbnailEvent(message, event: 'destination-check-failed');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    if (mediaKind == _ThumbnailMediaKind.image) {
      final nativeGenerated = await _generateNativeImageThumbnail(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
      );
      if (nativeGenerated != null) {
        _logGenerated(message, nativeGenerated, stopwatch.elapsedMilliseconds);
        return nativeGenerated;
      }
      final generated = await Isolate.run(
        () => _generateImageThumbnail(
          sourcePath: sourcePath,
          destinationPath: destinationPath,
          maxWidth: thumbnailWidth,
          maxHeight: thumbnailHeight,
        ),
      );
      final result = generated ? destinationPath : null;
      _logGenerated(message, result, stopwatch.elapsedMilliseconds);
      return result;
    }

    return null;
  }

  void _logGenerated(Message message, String? path, int elapsedMs) {
    _logThumbnailEvent(
      message,
      event: path == null ? 'generated-failed' : 'generated',
      path: path,
      elapsedMs: elapsedMs,
    );
  }

  void _logThumbnailEvent(
    Message message, {
    required String event,
    String? path,
    int? elapsedMs,
  }) {
    diag.log(
      '[chat_media] thumbnail ${path == null ? "failed" : "generated"} '
      'event=$event '
      'messageId=${message.id} file=${message.fileName ?? message.text} '
      'mime=${message.mimeType ?? ""} local=${message.localFilePath ?? ""} '
      'thumb=${message.thumbnailPath ?? ""} path=${path ?? ""} '
      'elapsedMs=${elapsedMs ?? -1}',
      name: 'chat',
      level: 900,
    );
  }

  _ThumbnailMediaKind? _mediaKind(Message message) {
    final mime = message.mimeType?.trim().toLowerCase();
    if (mime != null && mime.startsWith('image/')) {
      return _ThumbnailMediaKind.image;
    }
    if (mime != null && mime.startsWith('video/')) {
      return _ThumbnailMediaKind.video;
    }
    if (message.isImage) {
      return _ThumbnailMediaKind.image;
    }
    if (message.isVideo) {
      return _ThumbnailMediaKind.video;
    }
    return null;
  }

  Future<String?> _generateNativeImageThumbnail({
    required String sourcePath,
    required String destinationPath,
  }) async {
    try {
      final generated = await _channel
          .invokeMethod<bool>('generateImageThumbnail', <String, Object>{
            'sourcePath': sourcePath,
            'destinationPath': destinationPath,
            'maxWidth': thumbnailWidth,
            'maxHeight': thumbnailHeight,
          });
      return generated == true ? destinationPath : null;
    } catch (error) {
      diag.log(
        '[chat_media] thumbnail native-image exception source=$sourcePath '
        'dest=$destinationPath error=$error',
        name: 'chat',
        level: 900,
      );
      return null;
    }
  }

  String? _thumbnailPath({
    required String sourcePath,
    required String messageId,
  }) {
    final parent = File(sourcePath).parent.path;
    if (parent.isEmpty) {
      return null;
    }
    final safeId = messageId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$parent/$safeId$thumbnailSuffix';
  }
}

enum _ThumbnailMediaKind { image, video }

bool _generateImageThumbnail({
  required String sourcePath,
  required String destinationPath,
  required int maxWidth,
  required int maxHeight,
}) {
  try {
    final bytes = File(sourcePath).readAsBytesSync();
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      return false;
    }
    final oriented = img.bakeOrientation(decoded);
    final scale = [
      maxWidth / oriented.width,
      maxHeight / oriented.height,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    final resized = img.copyResize(
      oriented,
      width: (oriented.width * scale).round().clamp(1, maxWidth),
      height: (oriented.height * scale).round().clamp(1, maxHeight),
      interpolation: img.Interpolation.average,
    );
    File(destinationPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(resized, quality: 76), flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
