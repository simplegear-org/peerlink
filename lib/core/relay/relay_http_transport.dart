import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'relay_http_types.dart';

class RelayHttpTransport {
  final http.Client? httpClient;
  final void Function(String message) log;

  const RelayHttpTransport({required this.httpClient, required this.log});

  Future<http.Response?> sendPost(
    Uri uri, {
    required String body,
    required Duration timeout,
  }) async {
    if (httpClient == null) {
      return sendPostDirect(uri, body: body, timeout: timeout);
    }
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request('POST', uri)
          ..persistentConnection = false
          ..headers.addAll({
            'content-type': 'application/json',
            'accept': 'application/json',
            'connection': 'close',
          })
          ..body = body;
        final streamedResult = await awaitHttpOperation(
          () => httpClient!.send(request),
          timeout,
        );
        if (streamedResult.timedOut) {
          lastError = TimeoutException('POST request timed out', timeout);
          return null;
        }
        if (streamedResult.hasError) {
          lastError = streamedResult.error;
          final transient = isTransientHttpError(streamedResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final streamed = streamedResult.value;
        if (streamed == null) {
          return null;
        }
        final responseResult = await readStreamedResponse(
          streamed,
          timeout: timeout,
        );
        if (responseResult.timedOut) {
          lastError = const RelayResponseTimeout();
          return null;
        }
        if (responseResult.hasError) {
          lastError = responseResult.error;
          final transient = isTransientHttpError(responseResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        return responseResult.value;
      } catch (e) {
        lastError = e;
        final transient = isTransientHttpError(e);
        if (!transient || attempt >= 2) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    if (lastError != null && isTransientHttpError(lastError)) {
      return null;
    }
    throw HttpException('POST request failed: $lastError');
  }

  Future<http.Response?> sendGet(
    Uri uri, {
    RelayDownloadProgressCallback? onProgress,
    required Duration timeout,
  }) async {
    if (httpClient == null) {
      return sendGetDirect(uri, onProgress: onProgress, timeout: timeout);
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request('GET', uri)
          ..persistentConnection = false
          ..headers.addAll({
            'accept': 'application/json',
            'connection': 'close',
          });
        final streamedResult = await awaitHttpOperation(
          () => httpClient!.send(request),
          timeout,
        );
        if (streamedResult.timedOut) {
          lastError = TimeoutException('GET request timed out', timeout);
          return null;
        }
        if (streamedResult.hasError) {
          lastError = streamedResult.error;
          final transient = isTransientHttpError(streamedResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final streamed = streamedResult.value;
        if (streamed == null) {
          return null;
        }
        final responseResult = await readStreamedResponse(
          streamed,
          timeout: timeout,
          onProgress: onProgress,
        );
        if (responseResult.timedOut) {
          lastError = const RelayResponseTimeout();
          return null;
        }
        if (responseResult.hasError) {
          lastError = responseResult.error;
          final transient = isTransientHttpError(responseResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        return responseResult.value;
      } catch (e) {
        lastError = e;
        final transient = isTransientHttpError(e);
        if (!transient || attempt >= 2) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    if (lastError != null && isTransientHttpError(lastError)) {
      return null;
    }
    throw HttpException('GET request failed: $lastError');
  }

  Future<RelayAwaitResult<T>> awaitHttpOperation<T>(
    Future<T> Function() operation,
    Duration timeout,
  ) async {
    final completer = Completer<RelayAwaitResult<T>>();
    Timer? timeoutTimer;

    void complete(RelayAwaitResult<T> result) {
      if (completer.isCompleted) {
        return;
      }
      timeoutTimer?.cancel();
      completer.complete(result);
    }

    runZonedGuarded(
      () {
        timeoutTimer = Timer(
          timeout,
          () => complete(RelayAwaitResult<T>.timedOut()),
        );
        Future<T>.sync(operation).then(
          (value) => complete(RelayAwaitResult<T>.value(value)),
          onError: (Object error, StackTrace stackTrace) {
            complete(RelayAwaitResult<T>.error(error, stackTrace));
          },
        );
      },
      (Object error, StackTrace stackTrace) {
        if (completer.isCompleted) {
          log('HTTP late zone error ignored error=$error');
          return;
        }
        complete(RelayAwaitResult<T>.error(error, stackTrace));
      },
    );

    return completer.future.whenComplete(() => timeoutTimer?.cancel());
  }

  Future<http.Response?> sendPostDirect(
    Uri uri, {
    required String body,
    required Duration timeout,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final client = createRawHttpClientForUri(uri, timeout: timeout);
      try {
        final requestResult = await awaitHttpOperation(
          () => client.postUrl(uri),
          timeout,
        );
        if (requestResult.timedOut) {
          lastError = TimeoutException('POST open timed out', timeout);
          return null;
        }
        if (requestResult.hasError) {
          lastError = requestResult.error;
          final transient = isTransientHttpError(requestResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final request = requestResult.value;
        if (request == null) {
          return null;
        }
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        request.write(body);

        final responseResult = await awaitHttpOperation(
          () => request.close(),
          timeout,
        );
        if (responseResult.timedOut) {
          lastError = TimeoutException('POST close timed out', timeout);
          return null;
        }
        if (responseResult.hasError) {
          lastError = responseResult.error;
          final transient = isTransientHttpError(responseResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final response = responseResult.value;
        if (response == null) {
          return null;
        }
        final bodyResult = await readHttpClientResponse(
          response,
          timeout: timeout,
        );
        if (bodyResult.timedOut) {
          lastError = const RelayResponseTimeout();
          return null;
        }
        if (bodyResult.hasError) {
          lastError = bodyResult.error;
          final transient = isTransientHttpError(bodyResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        return bodyResult.value;
      } catch (e) {
        lastError = e;
        final transient = isTransientHttpError(e);
        if (!transient || attempt >= 2) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      } finally {
        client.close(force: true);
      }
    }
    if (lastError != null && isTransientHttpError(lastError)) {
      return null;
    }
    throw HttpException('POST request failed: $lastError');
  }

  Future<http.Response?> sendGetDirect(
    Uri uri, {
    RelayDownloadProgressCallback? onProgress,
    required Duration timeout,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final client = createRawHttpClientForUri(uri, timeout: timeout);
      try {
        final requestResult = await awaitHttpOperation(
          () => client.getUrl(uri),
          timeout,
        );
        if (requestResult.timedOut) {
          lastError = TimeoutException('GET open timed out', timeout);
          return null;
        }
        if (requestResult.hasError) {
          lastError = requestResult.error;
          final transient = isTransientHttpError(requestResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final request = requestResult.value;
        if (request == null) {
          return null;
        }
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.connectionHeader, 'close');

        final responseResult = await awaitHttpOperation(
          () => request.close(),
          timeout,
        );
        if (responseResult.timedOut) {
          lastError = TimeoutException('GET close timed out', timeout);
          return null;
        }
        if (responseResult.hasError) {
          lastError = responseResult.error;
          final transient = isTransientHttpError(responseResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        final response = responseResult.value;
        if (response == null) {
          return null;
        }
        final bodyResult = await readHttpClientResponse(
          response,
          timeout: timeout,
          onProgress: onProgress,
        );
        if (bodyResult.timedOut) {
          lastError = const RelayResponseTimeout();
          return null;
        }
        if (bodyResult.hasError) {
          lastError = bodyResult.error;
          final transient = isTransientHttpError(bodyResult.error);
          if (!transient || attempt >= 2) {
            break;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        return bodyResult.value;
      } catch (e) {
        lastError = e;
        final transient = isTransientHttpError(e);
        if (!transient || attempt >= 2) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      } finally {
        client.close(force: true);
      }
    }
    if (lastError != null && isTransientHttpError(lastError)) {
      return null;
    }
    throw HttpException('GET request failed: $lastError');
  }

  Future<RelayAwaitResult<http.Response>> readStreamedResponse(
    http.StreamedResponse streamed, {
    required Duration timeout,
    RelayDownloadProgressCallback? onProgress,
  }) async {
    final completer = Completer<RelayAwaitResult<http.Response>>();
    final rawContentLength = streamed.contentLength ?? -1;
    final totalBytes = rawContentLength < 0 ? 0 : rawContentLength;
    final chunks = <List<int>>[];
    StreamSubscription<List<int>>? subscription;
    Timer? idleTimer;
    var receivedBytes = 0;

    void complete(RelayAwaitResult<http.Response> result) {
      if (completer.isCompleted) {
        return;
      }
      idleTimer?.cancel();
      unawaited(subscription?.cancel());
      completer.complete(result);
    }

    void restartIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(
        timeout,
        () => complete(const RelayAwaitResult<http.Response>.timedOut()),
      );
    }

    restartIdleTimer();
    subscription = streamed.stream.listen(
      (chunk) {
        restartIdleTimer();
        chunks.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          status: 'Загрузка',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        complete(RelayAwaitResult<http.Response>.error(error, stackTrace));
      },
      onDone: () {
        final bytes = Uint8List(receivedBytes);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        complete(
          RelayAwaitResult<http.Response>.value(
            http.Response.bytes(
              bytes,
              streamed.statusCode,
              headers: streamed.headers,
              request: streamed.request,
              reasonPhrase: streamed.reasonPhrase,
            ),
          ),
        );
      },
      cancelOnError: false,
    );

    return completer.future;
  }

  Future<RelayAwaitResult<http.Response>> readHttpClientResponse(
    HttpClientResponse response, {
    required Duration timeout,
    RelayDownloadProgressCallback? onProgress,
  }) async {
    final completer = Completer<RelayAwaitResult<http.Response>>();
    final totalBytes = response.contentLength < 0 ? 0 : response.contentLength;
    final chunks = <List<int>>[];
    StreamSubscription<List<int>>? subscription;
    Timer? idleTimer;
    var receivedBytes = 0;

    void complete(RelayAwaitResult<http.Response> result) {
      if (completer.isCompleted) {
        return;
      }
      idleTimer?.cancel();
      unawaited(subscription?.cancel());
      completer.complete(result);
    }

    void restartIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(
        timeout,
        () => complete(const RelayAwaitResult<http.Response>.timedOut()),
      );
    }

    restartIdleTimer();
    subscription = response.listen(
      (chunk) {
        restartIdleTimer();
        chunks.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          status: 'Загрузка',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        complete(RelayAwaitResult<http.Response>.error(error, stackTrace));
      },
      onDone: () {
        final bytes = Uint8List(receivedBytes);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        complete(
          RelayAwaitResult<http.Response>.value(
            http.Response.bytes(
              bytes,
              response.statusCode,
              headers: headersFromHttpClientResponse(response),
              reasonPhrase: response.reasonPhrase,
            ),
          ),
        );
      },
      cancelOnError: false,
    );

    return completer.future;
  }

  bool isTransientHttpError(Object? error) {
    if (error is TimeoutException ||
        error is RelayResponseTimeout ||
        error is http.ClientException ||
        error is SocketException ||
        error is HttpException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('connection terminated') ||
        text.contains('connection refused') ||
        text.contains('broken pipe') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
  }

  HttpClient createRawHttpClientForUri(Uri uri, {required Duration timeout}) {
    final io = HttpClient()..connectionTimeout = timeout;
    if (uri.scheme == 'https') {
      // Relay servers are explicitly user-configured/self-hosted, so accept
      // host-matching self-signed certs for HTTPS relay transport.
      io.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            return host == uri.host;
          };
    }
    return io;
  }

  Map<String, String> headersFromHttpClientResponse(
    HttpClientResponse response,
  ) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return headers;
  }
}
