import 'dart:async';
import 'dart:typed_data';

import '../../core/relay/relay_models.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/storage_service.dart';
import '../models/message.dart';

typedef RelayMediaDownloadProgressCallback =
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    });

typedef RelayMediaUploadProgressCallback =
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    });

typedef RelayMediaDownloadOperation =
    Future<RelayBlobDownload> Function(
      RelayMediaDownloadProgressCallback onProgress,
    );

typedef RelayMediaUploadOperation =
    Future<String> Function(RelayMediaUploadProgressCallback onProgress);

typedef RelayMediaRestoreStageCallback =
    FutureOr<void> Function({
      required int? transferredBytes,
      required double? sendProgress,
      required String transferStatus,
    });

typedef RelayMediaSaveBytes =
    Future<String> Function({
      required String fileName,
      required Uint8List bytes,
    });

typedef RelayMediaPayloadTransform =
    Future<Uint8List> Function(RelayBlobDownload blob);

enum RelayMediaRestoreStatus { saved, notFound, failed }

class RelayMediaRestoreResult {
  final RelayMediaRestoreStatus status;
  final String? path;
  final Object? error;
  final StackTrace? stackTrace;

  const RelayMediaRestoreResult._({
    required this.status,
    this.path,
    this.error,
    this.stackTrace,
  });

  factory RelayMediaRestoreResult.saved(String path) {
    return RelayMediaRestoreResult._(
      status: RelayMediaRestoreStatus.saved,
      path: path,
    );
  }

  factory RelayMediaRestoreResult.notFound(String blobId) {
    return RelayMediaRestoreResult._(
      status: RelayMediaRestoreStatus.notFound,
      error: StateError('Relay blob not found: $blobId'),
    );
  }

  factory RelayMediaRestoreResult.failed(
    Object error, [
    StackTrace? stackTrace,
  ]) {
    return RelayMediaRestoreResult._(
      status: RelayMediaRestoreStatus.failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  bool get isSaved => status == RelayMediaRestoreStatus.saved;
  bool get isNotFound => status == RelayMediaRestoreStatus.notFound;
  String get errorKind => isNotFound ? 'not_found' : 'transient';
}

class RelayMediaUploadResult {
  final String? blobId;
  final Object? error;
  final StackTrace? stackTrace;

  const RelayMediaUploadResult._({this.blobId, this.error, this.stackTrace});

  factory RelayMediaUploadResult.uploaded(String blobId) {
    return RelayMediaUploadResult._(blobId: blobId);
  }

  factory RelayMediaUploadResult.failed(
    Object error, [
    StackTrace? stackTrace,
  ]) {
    return RelayMediaUploadResult._(error: error, stackTrace: stackTrace);
  }

  bool get isUploaded => blobId != null && blobId!.isNotEmpty;
}

class RelayMediaTransferService {
  static const String incomingFetchStatus = 'Получение из relay';
  static const String incomingRetryStatus = 'Повторная загрузка';
  static const String incomingDownloadStatus = 'Загрузка';
  static const String incomingCompleteStatus = 'Загрузка завершена';
  static const String incomingDecryptStatus = 'Расшифровка';
  static const String incomingSaveStatus = 'Сохранение';
  static const String incomingErrorStatus = 'Ошибка загрузки';

  const RelayMediaTransferService();

  static String mediaKey(String peerId, String messageId) =>
      '$peerId::$messageId';

  Future<RelayMediaUploadResult> uploadBlob({
    required String peerId,
    required String messageId,
    required RelayMediaUploadOperation upload,
    required RelayMediaUploadProgressCallback onProgress,
  }) async {
    try {
      final blobId = await upload(({
        required int sentBytes,
        required int totalBytes,
        required String status,
      }) {
        try {
          onProgress(
            sentBytes: sentBytes,
            totalBytes: totalBytes,
            status: status,
          );
        } catch (error) {
          _log(
            'upload progress failed peer=$peerId messageId=$messageId '
            'error=$error',
          );
        }
      });
      if (blobId.isEmpty) {
        return RelayMediaUploadResult.failed(
          StateError('Relay blob upload returned empty blobId'),
        );
      }
      return RelayMediaUploadResult.uploaded(blobId);
    } catch (error, stackTrace) {
      _log('upload failed peer=$peerId messageId=$messageId error=$error');
      return RelayMediaUploadResult.failed(error, stackTrace);
    }
  }

  Future<RelayMediaRestoreResult> restoreIncomingMedia({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required RelayMediaDownloadOperation downloadBlob,
    required RelayMediaSaveBytes saveBytes,
    required RelayMediaDownloadProgressCallback onProgress,
    required RelayMediaRestoreStageCallback onStage,
    RelayMediaPayloadTransform? transformPayload,
    String? transformStatus,
    int attempts = 2,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) async {
    await _safeStage(
      peerId: peerId,
      messageId: messageId,
      onStage: onStage,
      transferredBytes: 0,
      sendProgress: null,
      transferStatus: incomingFetchStatus,
    );

    final retryResult = await _downloadBlobWithRetry(
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      attempts: attempts,
      retryDelay: retryDelay,
      operation: downloadBlob,
      onProgress: onProgress,
    );
    final blob = retryResult.download;
    if (blob == null) {
      return RelayMediaRestoreResult.failed(
        retryResult.error ?? StateError('Relay blob download failed'),
        retryResult.stackTrace,
      );
    }
    if (blob.isNotFound) {
      return RelayMediaRestoreResult.notFound(blobId);
    }

    Uint8List bytes;
    try {
      if (transformPayload != null) {
        await _safeStage(
          peerId: peerId,
          messageId: messageId,
          onStage: onStage,
          transferredBytes: blob.sizeBytes,
          sendProgress: 0.85,
          transferStatus: transformStatus ?? incomingDecryptStatus,
        );
        bytes = await transformPayload(blob);
      } else {
        bytes = blob.payload;
      }
    } catch (error, stackTrace) {
      _log(
        'restore transform failed peer=$peerId messageId=$messageId '
        'blobId=$blobId error=$error',
      );
      return RelayMediaRestoreResult.failed(error, stackTrace);
    }

    await _safeStage(
      peerId: peerId,
      messageId: messageId,
      onStage: onStage,
      transferredBytes: bytes.length,
      sendProgress: 0.95,
      transferStatus: incomingSaveStatus,
    );

    try {
      final path = await saveBytes(
        fileName: fileName ?? blob.fileName,
        bytes: bytes,
      );
      if (path.isEmpty) {
        return RelayMediaRestoreResult.failed(
          StateError('Relay media save returned empty path'),
        );
      }
      return RelayMediaRestoreResult.saved(path);
    } catch (error, stackTrace) {
      _log(
        'restore save failed peer=$peerId messageId=$messageId '
        'blobId=$blobId error=$error',
      );
      return RelayMediaRestoreResult.failed(error, stackTrace);
    }
  }

  Future<_RelayBlobDownloadRetryResult> _downloadBlobWithRetry({
    required String peerId,
    required String messageId,
    required String blobId,
    required int attempts,
    required Duration retryDelay,
    required RelayMediaDownloadOperation operation,
    required RelayMediaDownloadProgressCallback onProgress,
  }) async {
    assert(attempts > 0);
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < attempts; attempt++) {
      void progressCallback({
        required int receivedBytes,
        required int totalBytes,
        required String status,
      }) {
        try {
          onProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            status: status,
          );
        } catch (error) {
          _log(
            'download progress failed peer=$peerId messageId=$messageId '
            'blobId=$blobId error=$error',
          );
        }
      }

      Future<RelayBlobDownload> attemptFuture;
      try {
        attemptFuture = operation(progressCallback);
      } catch (error, stackTrace) {
        attemptFuture = Future<RelayBlobDownload>.error(error, stackTrace);
      }
      final result = await attemptFuture.then<_RelayBlobDownloadAttemptResult>(
        (download) => _RelayBlobDownloadAttemptResult(download: download),
        onError: (Object error, StackTrace stackTrace) {
          return _RelayBlobDownloadAttemptResult(
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      final download = result.download;
      if (download != null) {
        return _RelayBlobDownloadRetryResult(download: download);
      }

      lastError = result.error;
      lastStackTrace = result.stackTrace;
      _log(
        'download attempt failed peer=$peerId messageId=$messageId '
        'blobId=$blobId attempt=${attempt + 1}/$attempts error=$lastError',
      );
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(retryDelay);
      }
    }

    return _RelayBlobDownloadRetryResult(
      error:
          lastError ?? StateError('blob-fetch failed for $attempts attempts'),
      stackTrace: lastStackTrace,
    );
  }

  Future<void> _safeStage({
    required String peerId,
    required String messageId,
    required RelayMediaRestoreStageCallback onStage,
    required int? transferredBytes,
    required double? sendProgress,
    required String transferStatus,
  }) async {
    try {
      await onStage(
        transferredBytes: transferredBytes,
        sendProgress: sendProgress,
        transferStatus: transferStatus,
      );
    } catch (error) {
      _log(
        'stage update failed peer=$peerId messageId=$messageId '
        'status=$transferStatus error=$error',
      );
    }
  }

  void _log(String message) {
    AppFileLogger.log('[relay_media] $message');
  }
}

class _RelayBlobDownloadRetryResult {
  final RelayBlobDownload? download;
  final Object? error;
  final StackTrace? stackTrace;

  const _RelayBlobDownloadRetryResult({
    this.download,
    this.error,
    this.stackTrace,
  });
}

class _RelayBlobDownloadAttemptResult {
  final RelayBlobDownload? download;
  final Object? error;
  final StackTrace? stackTrace;

  const _RelayBlobDownloadAttemptResult({
    this.download,
    this.error,
    this.stackTrace,
  });
}

class RelayMediaRetryCoordinator {
  static const int maxAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 4);
  static const String stateKey = 'incoming_relay_media_retry_v1';

  final SecureStorageBox settingsBox;
  final Map<String, Timer> _timers = <String, Timer>{};

  RelayMediaRetryCoordinator({required this.settingsBox});

  static String mediaKey(String peerId, String messageId) =>
      RelayMediaTransferService.mediaKey(peerId, messageId);

  void cancelTimerForKey(String key) {
    final timer = _timers.remove(key);
    timer?.cancel();
  }

  Future<void> clear(String peerId, String messageId) async {
    final key = mediaKey(peerId, messageId);
    cancelTimerForKey(key);
    await clearState(key);
  }

  int attemptsForKey(String key) {
    final value = _states()[key]?['attempts'];
    return value is int ? value : 0;
  }

  bool isDue(String key) {
    if (attemptsForKey(key) >= maxAttempts) {
      return false;
    }
    final nextRetryAtMs = _nextRetryAtMsForKey(key);
    if (nextRetryAtMs == null) {
      return true;
    }
    return DateTime.now().millisecondsSinceEpoch >= nextRetryAtMs;
  }

  Future<bool> recordFailure({
    required String peerId,
    required String messageId,
    required String errorKind,
  }) async {
    final key = mediaKey(peerId, messageId);
    final states = _states();
    final current = states[key] ?? <String, dynamic>{};
    final previousAttempts = current['attempts'];
    final attempts = errorKind == 'not_found'
        ? maxAttempts
        : (previousAttempts is int ? previousAttempts : 0) + 1;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backoffMs = retryDelay.inMilliseconds * attempts;
    states[key] = <String, dynamic>{
      'peerId': peerId,
      'messageId': messageId,
      'attempts': attempts,
      'lastAttemptAtMs': nowMs,
      'nextRetryAtMs': attempts >= maxAttempts ? 0 : nowMs + backoffMs,
      'lastErrorKind': errorKind,
    };
    await _saveStates(states);
    return attempts < maxAttempts;
  }

  void scheduleRetry({
    required String peerId,
    required String messageId,
    required Future<Message?> Function(String peerId, String messageId)
    findMessage,
    required Future<void> Function(String peerId, String messageId)
    markRetrying,
    required void Function(Message message, {required bool isGroup})
    restoreInBackground,
  }) {
    final key = mediaKey(peerId, messageId);
    if (_timers.containsKey(key)) {
      return;
    }
    if (attemptsForKey(key) >= maxAttempts) {
      return;
    }
    final nextRetryAtMs = _nextRetryAtMsForKey(key);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final delayMs = nextRetryAtMs == null
        ? retryDelay.inMilliseconds
        : (nextRetryAtMs - nowMs).clamp(0, 1 << 31).toInt();
    _timers[key] = Timer(Duration(milliseconds: delayMs), () async {
      _timers.remove(key);
      final message = await findMessage(peerId, messageId);
      if (message == null ||
          !message.incoming ||
          message.kind != MessageKind.file ||
          (message.localFilePath?.isNotEmpty ?? false)) {
        await clear(peerId, messageId);
        return;
      }
      try {
        await markRetrying(peerId, messageId);
        final transferId = (message.transferId ?? '').trim();
        if (transferId.startsWith('dirblob:')) {
          restoreInBackground(message, isGroup: false);
        } else if (transferId.startsWith('grpblob:')) {
          restoreInBackground(message, isGroup: true);
        }
      } catch (error) {
        AppFileLogger.log(
          '[relay_media_retry] retry start failed peer=$peerId '
          'messageId=$messageId error=$error',
        );
      }
    });
  }

  Future<void> clearState(String key) async {
    final states = _states();
    if (states.remove(key) == null) {
      return;
    }
    await _saveStates(states);
  }

  void dispose() {
    final timers = List<Timer>.from(_timers.values);
    for (final timer in timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  Map<String, Map<String, dynamic>> _states() {
    final raw = settingsBox.get(stateKey);
    if (raw is! Map) {
      return <String, Map<String, dynamic>>{};
    }
    final result = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        result[key] = Map<String, dynamic>.from(value);
      }
    });
    return result;
  }

  Future<void> _saveStates(Map<String, Map<String, dynamic>> states) async {
    await settingsBox.put(stateKey, states);
  }

  int? _nextRetryAtMsForKey(String key) {
    final value = _states()[key]?['nextRetryAtMs'];
    return value is int && value > 0 ? value : null;
  }
}
