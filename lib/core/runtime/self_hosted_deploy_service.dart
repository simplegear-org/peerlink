import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../turn/turn_server_config.dart';
import 'self_hosted_deploy_command_builder.dart';
import 'server_runtime_utils.dart';

class SelfHostedDeployPreview {
  final String host;
  final String bootstrapEndpoint;
  final String relayEndpoint;
  final List<TurnServerConfig> turnServers;

  const SelfHostedDeployPreview({
    required this.host,
    required this.bootstrapEndpoint,
    required this.relayEndpoint,
    required this.turnServers,
  });
}

class SelfHostedDeployResult {
  final String host;
  final String bootstrapEndpoint;
  final String relayEndpoint;
  final List<TurnServerConfig> turnServers;

  const SelfHostedDeployResult({
    required this.host,
    required this.bootstrapEndpoint,
    required this.relayEndpoint,
    required this.turnServers,
  });
}

class SelfHostedRemoteCommandException implements Exception {
  final int exitCode;
  final String lastLines;

  const SelfHostedRemoteCommandException({
    required this.exitCode,
    this.lastLines = '',
  });

  @override
  String toString() {
    if (lastLines.trim().isEmpty) {
      return 'Remote command exited with code $exitCode';
    }
    return 'Remote command exited with code $exitCode\nLast lines:\n$lastLines';
  }
}

enum SelfHostedDeployInputError {
  invalidHost,
  missingUsername,
  missingPassword,
}

class SelfHostedDeployInputException implements Exception {
  final SelfHostedDeployInputError error;

  const SelfHostedDeployInputException(this.error);

  @override
  String toString() => 'Self-hosted deploy input error: ${error.name}';
}

enum SelfHostedDeployError {
  commandFailedBeforeServiceChecks,
  completionMarkerMissing,
}

class SelfHostedDeployException implements Exception {
  final SelfHostedDeployError error;
  final String details;

  const SelfHostedDeployException(this.error, {this.details = ''});

  @override
  String toString() {
    if (details.trim().isEmpty) {
      return 'Self-hosted deploy error: ${error.name}';
    }
    return 'Self-hosted deploy error: ${error.name}\n$details';
  }
}

enum SelfHostedDeployStageKind {
  connectToServer,
  updateOperatingSystem,
  cloneRepository,
  runDeploy,
  installDocker,
  installDockerCompose,
  installOpenSsl,
  generateCertificate,
  generateHaproxy,
  generateTurn,
  deploymentComplete,
  bootstrapEndpoint,
  relayEndpoint,
  testBootstrapOk,
  testBootstrapFail,
  testRelayOk,
  testRelayFail,
  testTurnOk,
  testTurnFail,
  unknown,
}

class SelfHostedDeployStageEvent {
  final int stage;
  final int totalStages;
  final SelfHostedDeployStageKind kind;
  final String details;
  final String rawMessage;

  const SelfHostedDeployStageEvent({
    required this.stage,
    required this.totalStages,
    required this.kind,
    this.details = '',
    this.rawMessage = '',
  });
}

typedef SelfHostedDeployStageListener =
    void Function(SelfHostedDeployStageEvent event);

enum SelfHostedDeployServiceKind { bootstrap, relay, turn }

enum SelfHostedDeployReadinessKind { readyAfterRetry, notReadyYet }

class SelfHostedDeployReadinessEvent {
  final SelfHostedDeployServiceKind service;
  final SelfHostedDeployReadinessKind kind;
  final int attempt;
  final String error;

  const SelfHostedDeployReadinessEvent({
    required this.service,
    required this.kind,
    required this.attempt,
    this.error = '',
  });
}

typedef SelfHostedDeployReadinessListener =
    void Function(SelfHostedDeployReadinessEvent event);

class SelfHostedDeployService {
  static const int _totalStages = 14;
  static const String _stagePrefix = '__PEERLINK_STAGE__:';
  static const String _bootstrapScriptUrl =
      'https://raw.githubusercontent.com/simplegear-org/peerlink_servers/main/bootstrap.sh';
  static const String _deploySuccessMarker = '__PEERLINK_DEPLOY_OK__';
  static const String _deployCompletePhrase = 'Deployment complete!';
  static const String _deployRepoUrl =
      'https://github.com/simplegear-org/peerlink_servers.git';
  static const String _deployBranch = 'main';
  static const String _deployDirName = 'peerlink_servers';
  static const Duration _postDeployRetryWindow = Duration(seconds: 45);
  static const Duration _postDeployRetryDelay = Duration(seconds: 2);
  static const SelfHostedDeployCommandBuilder _commandBuilder =
      SelfHostedDeployCommandBuilder(
        bootstrapScriptUrl: _bootstrapScriptUrl,
        deployRepoUrl: _deployRepoUrl,
        deployBranch: _deployBranch,
        deployDirName: _deployDirName,
        deploySuccessMarker: _deploySuccessMarker,
      );

  SelfHostedDeployPreview? previewForHost(String host) {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }
    return SelfHostedDeployPreview(
      host: normalizedHost,
      bootstrapEndpoint: 'wss://$normalizedHost:443',
      relayEndpoint: 'https://$normalizedHost:444',
      turnServers: <TurnServerConfig>[
        const TurnServerConfig(
          url: '',
          username: 'peerlink',
          password: '',
          priority: 1000,
        ).copyWith(url: 'turn:$normalizedHost:3478?transport=udp'),
        const TurnServerConfig(
          url: '',
          username: 'peerlink',
          password: '',
          priority: 750,
        ).copyWith(url: 'turn:$normalizedHost:3478?transport=tcp'),
      ],
    );
  }

  Future<SelfHostedDeployResult> deploy({
    required String host,
    required String username,
    required String password,
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
    SelfHostedDeployReadinessListener? onReadiness,
  }) async {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw const SelfHostedDeployInputException(
        SelfHostedDeployInputError.invalidHost,
      );
    }
    if (username.trim().isEmpty) {
      throw const SelfHostedDeployInputException(
        SelfHostedDeployInputError.missingUsername,
      );
    }
    if (password.isEmpty) {
      throw const SelfHostedDeployInputException(
        SelfHostedDeployInputError.missingPassword,
      );
    }

    final turnUser = 'peerlink';
    final turnPassword = _generateTurnPassword();

    _emitStage(
      onProgress,
      onStage,
      1,
      SelfHostedDeployStageKind.connectToServer,
    );
    final socket = await SSHSocket.connect(
      normalizedHost,
      22,
      timeout: const Duration(seconds: 12),
    );
    final client = SSHClient(
      socket,
      username: username.trim(),
      onPasswordRequest: () => password,
    );

    try {
      await client.run('echo AUTH_OK >/dev/null 2>&1');

      final deployCommand = _commandBuilder.buildDeployCommand(
        publicHost: normalizedHost,
        turnUser: turnUser,
        turnPassword: turnPassword,
        loginPassword: password,
      );
      final deployText = await _runStreamingCommand(
        client: client,
        command: deployCommand,
        onProgress: onProgress,
        onStage: onStage,
      );
      if (!deployText.contains(_deploySuccessMarker)) {
        throw SelfHostedDeployException(
          SelfHostedDeployError.commandFailedBeforeServiceChecks,
          details: SelfHostedDeployCommandBuilder.lastLines(
            deployText,
            maxLines: 12,
          ),
        );
      }
      if (deployText.isNotEmpty) {
        final cleaned = deployText.replaceAll(_deploySuccessMarker, '').trim();
        if (cleaned.isNotEmpty) {
          _log(
            onProgress,
            SelfHostedDeployCommandBuilder.lastLines(cleaned, maxLines: 6),
          );
        }
      }
      if (!deployText.contains(_deployCompletePhrase)) {
        throw const SelfHostedDeployException(
          SelfHostedDeployError.completionMarkerMissing,
        );
      }

      final resolvedBootstrapEndpoint = await _resolveBootstrapEndpoint(
        normalizedHost,
        onProgress: onProgress,
        onStage: onStage,
      );
      final resolvedRelayEndpoint = await _resolveRelayEndpoint(
        normalizedHost,
        onProgress: onProgress,
        onStage: onStage,
      );

      try {
        await _waitForServiceReadiness(
          service: SelfHostedDeployServiceKind.bootstrap,
          onProgress: onProgress,
          onReadiness: onReadiness,
          action: () => _verifyBootstrap(Uri.parse(resolvedBootstrapEndpoint)),
        );
        _emitStage(
          onProgress,
          onStage,
          12,
          SelfHostedDeployStageKind.testBootstrapOk,
        );
      } catch (_) {
        _emitStage(
          onProgress,
          onStage,
          12,
          SelfHostedDeployStageKind.testBootstrapFail,
        );
        rethrow;
      }

      try {
        await _waitForServiceReadiness(
          service: SelfHostedDeployServiceKind.relay,
          onProgress: onProgress,
          onReadiness: onReadiness,
          action: () => _verifyRelay(Uri.parse(resolvedRelayEndpoint)),
        );
        _emitStage(
          onProgress,
          onStage,
          13,
          SelfHostedDeployStageKind.testRelayOk,
        );
      } catch (_) {
        _emitStage(
          onProgress,
          onStage,
          13,
          SelfHostedDeployStageKind.testRelayFail,
        );
        rethrow;
      }

      try {
        await _waitForServiceReadiness(
          service: SelfHostedDeployServiceKind.turn,
          onProgress: onProgress,
          onReadiness: onReadiness,
          action: () => _verifyTurn(normalizedHost),
        );
        _emitStage(
          onProgress,
          onStage,
          14,
          SelfHostedDeployStageKind.testTurnOk,
        );
      } catch (_) {
        _emitStage(
          onProgress,
          onStage,
          14,
          SelfHostedDeployStageKind.testTurnFail,
        );
        rethrow;
      }
      return SelfHostedDeployResult(
        host: normalizedHost,
        bootstrapEndpoint: resolvedBootstrapEndpoint,
        relayEndpoint: resolvedRelayEndpoint,
        turnServers: <TurnServerConfig>[
          TurnServerConfig(
            url: 'turn:$normalizedHost:3478?transport=udp',
            username: turnUser,
            password: turnPassword,
            priority: 1000,
          ),
          TurnServerConfig(
            url: 'turn:$normalizedHost:3478?transport=tcp',
            username: turnUser,
            password: turnPassword,
            priority: 750,
          ),
        ],
      );
    } finally {
      client.close();
    }
  }

  Future<String> _runStreamingCommand({
    required SSHClient client,
    required String command,
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
  }) async {
    final session = await client.execute(command);
    final output = StringBuffer();

    String stdoutPending = '';
    String stderrPending = '';

    void emitLine(String line, {required bool isError}) {
      final clean = line.replaceAll('\r', '').trimRight();
      if (clean.isEmpty) {
        return;
      }
      if (clean == _deploySuccessMarker) {
        return;
      }
      if (_tryEmitStageMessage(clean, onProgress, onStage)) {
        return;
      }
      if (isError) {
        _log(onProgress, '[stderr] $clean');
      }
    }

    void consumeChunk(String chunk, {required bool isError}) {
      output.write(chunk);
      if (isError) {
        stderrPending += chunk;
        while (true) {
          final index = stderrPending.indexOf('\n');
          if (index < 0) {
            break;
          }
          final line = stderrPending.substring(0, index);
          stderrPending = stderrPending.substring(index + 1);
          emitLine(line, isError: true);
        }
        return;
      }

      stdoutPending += chunk;
      while (true) {
        final index = stdoutPending.indexOf('\n');
        if (index < 0) {
          break;
        }
        final line = stdoutPending.substring(0, index);
        stdoutPending = stdoutPending.substring(index + 1);
        emitLine(line, isError: false);
      }
    }

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    session.stdout.listen(
      (data) =>
          consumeChunk(utf8.decode(data, allowMalformed: true), isError: false),
      onDone: () {
        if (stdoutPending.isNotEmpty) {
          emitLine(stdoutPending, isError: false);
          stdoutPending = '';
        }
        stdoutDone.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!stdoutDone.isCompleted) {
          stdoutDone.completeError(error, stackTrace);
        }
      },
      cancelOnError: true,
    );

    session.stderr.listen(
      (data) =>
          consumeChunk(utf8.decode(data, allowMalformed: true), isError: true),
      onDone: () {
        if (stderrPending.isNotEmpty) {
          emitLine(stderrPending, isError: true);
          stderrPending = '';
        }
        stderrDone.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!stderrDone.isCompleted) {
          stderrDone.completeError(error, stackTrace);
        }
      },
      cancelOnError: true,
    );

    await Future.wait<void>([
      stdoutDone.future,
      stderrDone.future,
      session.done,
    ]);

    final exitCode = session.exitCode;
    if (exitCode != null && exitCode != 0) {
      throw SelfHostedRemoteCommandException(
        exitCode: exitCode,
        lastLines: SelfHostedDeployCommandBuilder.lastLines(
          output.toString(),
          maxLines: 12,
        ),
      );
    }

    return output.toString().trim();
  }

  Future<String> _resolveBootstrapEndpoint(
    String host, {
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
  }) async {
    final candidate = 'wss://$host:443';
    _emitStage(
      onProgress,
      onStage,
      12,
      SelfHostedDeployStageKind.bootstrapEndpoint,
      details: candidate,
    );
    return candidate;
  }

  Future<String> _resolveRelayEndpoint(
    String host, {
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
  }) async {
    final candidate = 'https://$host:444';
    _emitStage(
      onProgress,
      onStage,
      13,
      SelfHostedDeployStageKind.relayEndpoint,
      details: candidate,
    );
    return candidate;
  }

  Future<void> _verifyBootstrap(Uri endpoint) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (cert, host, port) => true;
    final ws = await WebSocket.connect(
      endpoint.toString(),
      customClient: client,
    ).timeout(const Duration(seconds: 8));
    await ws.close();
    client.close(force: true);
  }

  Future<void> _verifyRelay(Uri endpoint) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      final req = await client.getUrl(endpoint.resolve('/health'));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw StateError('relay health status=${res.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verifyTurn(String host) async {
    final socket = await Socket.connect(
      host,
      3478,
      timeout: const Duration(seconds: 8),
    );
    socket.destroy();
  }

  Future<void> _waitForServiceReadiness({
    required SelfHostedDeployServiceKind service,
    required Future<void> Function() action,
    void Function(String message)? onProgress,
    SelfHostedDeployReadinessListener? onReadiness,
  }) async {
    final deadline = DateTime.now().add(_postDeployRetryWindow);
    late Object lastError;
    late StackTrace lastStackTrace;
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        await action();
        if (attempt > 1) {
          _emitReadiness(
            onProgress,
            onReadiness,
            SelfHostedDeployReadinessEvent(
              service: service,
              kind: SelfHostedDeployReadinessKind.readyAfterRetry,
              attempt: attempt,
            ),
          );
        }
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (DateTime.now().isAfter(deadline)) {
          Error.throwWithStackTrace(lastError, lastStackTrace);
        }
        _emitReadiness(
          onProgress,
          onReadiness,
          SelfHostedDeployReadinessEvent(
            service: service,
            kind: SelfHostedDeployReadinessKind.notReadyYet,
            attempt: attempt,
            error: '$error',
          ),
        );
        await Future<void>.delayed(_postDeployRetryDelay);
      }
    }
  }

  String _normalizeHost(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return '';
    }

    var value = raw;
    if (!value.contains('://')) {
      value = 'ssh://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      return '';
    }

    final host = uri.host.trim();
    if (host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.query.isNotEmpty) {
      return '';
    }

    final path = uri.path.trim();
    if (path.isNotEmpty && path != '/') {
      return '';
    }

    if (!ServerRuntimeUtils.isSafeHost(host)) {
      return '';
    }

    return host;
  }

  String _generateTurnPassword() {
    // Keep TURN credentials config-safe for coturn: avoid comment and parser
    // metacharacters such as '#', ';', ':', quotes, and whitespace.
    const alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final result = StringBuffer();
    for (var i = 0; i < 20; i++) {
      result.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return result.toString();
  }

  bool _tryEmitStageMessage(
    String line,
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
  ) {
    if (!line.startsWith(_stagePrefix)) {
      return false;
    }
    final payload = line.substring(_stagePrefix.length);
    final sep = payload.indexOf(':');
    if (sep <= 0 || sep == payload.length - 1) {
      return false;
    }
    final rawStage = payload.substring(0, sep).trim();
    final stage = int.tryParse(rawStage);
    if (stage == null || stage < 1 || stage > _totalStages) {
      return false;
    }
    final text = payload.substring(sep + 1).trim();
    if (text.isEmpty) {
      return false;
    }
    final kind = _stageKindFor(stage, text);
    _emitStage(onProgress, onStage, stage, kind, rawMessage: text);
    return true;
  }

  void _emitStage(
    void Function(String message)? onProgress,
    SelfHostedDeployStageListener? onStage,
    int stage,
    SelfHostedDeployStageKind kind, {
    String details = '',
    String rawMessage = '',
  }) {
    final event = SelfHostedDeployStageEvent(
      stage: stage,
      totalStages: _totalStages,
      kind: kind,
      details: details,
      rawMessage: rawMessage,
    );
    onStage?.call(event);
    if (onStage != null) {
      return;
    }
    _log(
      onProgress,
      'Stage $stage/$_totalStages: ${rawMessage.isEmpty ? kind.name : rawMessage}',
    );
  }

  SelfHostedDeployStageKind _stageKindFor(int stage, String message) {
    return switch (stage) {
      2 => SelfHostedDeployStageKind.updateOperatingSystem,
      3 => SelfHostedDeployStageKind.cloneRepository,
      4 => SelfHostedDeployStageKind.runDeploy,
      5 => SelfHostedDeployStageKind.installDocker,
      6 => SelfHostedDeployStageKind.installDockerCompose,
      7 => SelfHostedDeployStageKind.installOpenSsl,
      8 => SelfHostedDeployStageKind.generateCertificate,
      9 => SelfHostedDeployStageKind.generateHaproxy,
      10 => SelfHostedDeployStageKind.generateTurn,
      11 when message == _deployCompletePhrase =>
        SelfHostedDeployStageKind.deploymentComplete,
      _ => SelfHostedDeployStageKind.unknown,
    };
  }

  void _emitReadiness(
    void Function(String message)? onProgress,
    SelfHostedDeployReadinessListener? onReadiness,
    SelfHostedDeployReadinessEvent event,
  ) {
    onReadiness?.call(event);
    if (onReadiness != null) {
      return;
    }
    final service = event.service.name;
    final retry = '#${event.attempt}';
    final message = switch (event.kind) {
      SelfHostedDeployReadinessKind.readyAfterRetry =>
        '$service ready after retry $retry',
      SelfHostedDeployReadinessKind.notReadyYet =>
        '$service not ready yet, retry $retry: ${event.error}',
    };
    _log(onProgress, message);
  }

  void _log(void Function(String message)? sink, String message) {
    sink?.call(message);
  }
}
