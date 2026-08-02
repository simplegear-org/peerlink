import 'dart:io';

import 'package:http/http.dart' as http;

import 'relay_models.dart';

typedef RelayUploadProgressCallback =
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    });

typedef RelayDownloadProgressCallback =
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    });

class RelayAwaitResult<T> {
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
  final bool timedOut;

  const RelayAwaitResult.value(T this.value)
    : error = null,
      stackTrace = null,
      timedOut = false;

  const RelayAwaitResult.error(Object this.error, StackTrace this.stackTrace)
    : value = null,
      timedOut = false;

  const RelayAwaitResult.timedOut()
    : value = null,
      error = null,
      stackTrace = null,
      timedOut = true;

  bool get hasError => error != null;
}

class RelayResponseTimeout {
  const RelayResponseTimeout();

  @override
  String toString() => 'relay response timed out';
}

class RelayPostOutcome {
  final bool success;
  final String? error;

  const RelayPostOutcome({this.success = false, this.error});
}

class RelayFetchOutcome {
  final bool success;
  final List<RelayEnvelope> messages;
  final String? cursor;

  const RelayFetchOutcome({
    this.success = false,
    this.messages = const <RelayEnvelope>[],
    this.cursor,
  });
}

class RelayBlobFetchOutcome {
  final RelayBlobDownload? download;
  final String? error;

  const RelayBlobFetchOutcome({this.download, this.error});
}

class RelayBlobFetchServerOutcome {
  final Uri server;
  final RelayBlobFetchOutcome outcome;

  const RelayBlobFetchServerOutcome({
    required this.server,
    required this.outcome,
  });
}

class RelayBlobFetchBatchOutcome {
  final RelayBlobDownload? download;
  final List<String> errors;

  const RelayBlobFetchBatchOutcome({
    this.download,
    this.errors = const <String>[],
  });
}

class RelayHttpResponseReader {
  final Future<RelayAwaitResult<http.Response>> Function(
    http.StreamedResponse streamed, {
    required Duration timeout,
    RelayDownloadProgressCallback? onProgress,
  })
  readStreamedResponse;
  final Future<RelayAwaitResult<http.Response>> Function(
    HttpClientResponse response, {
    required Duration timeout,
    RelayDownloadProgressCallback? onProgress,
  })
  readHttpClientResponse;

  const RelayHttpResponseReader({
    required this.readStreamedResponse,
    required this.readHttpClientResponse,
  });
}
