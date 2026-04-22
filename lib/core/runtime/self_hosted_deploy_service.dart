import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../turn/turn_server_config.dart';

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

  Future<SelfHostedDeployResult> deploy({
    required String host,
    required String username,
    required String password,
    void Function(String message)? onProgress,
  }) async {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw const FormatException('Укажите адрес сервера');
    }
    if (username.trim().isEmpty) {
      throw const FormatException('Укажите логин');
    }
    if (password.isEmpty) {
      throw const FormatException('Укажите пароль');
    }

    final turnUser = 'peerlink';
    final turnPassword = _generateTurnPassword();

    _emitStage(
      onProgress,
      1,
      'Connect to server',
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

      final deployCommand = _buildDeployCommand(
        turnUser: turnUser,
        turnPassword: turnPassword,
        loginPassword: password,
      );
      final deployText = await _runStreamingCommand(
        client: client,
        command: deployCommand,
        onProgress: onProgress,
      );
      if (!deployText.contains(_deploySuccessMarker)) {
        if (deployText.isNotEmpty) {
          _log(onProgress, _lastLines(deployText, maxLines: 12));
        }
        throw StateError(
          'Команда развёртывания завершилась с ошибкой до проверки сервисов',
        );
      }
      if (deployText.isNotEmpty) {
        final cleaned = deployText
            .replaceAll(_deploySuccessMarker, '')
            .trim();
        if (cleaned.isNotEmpty) {
          _log(onProgress, _lastLines(cleaned, maxLines: 6));
        }
      }
      if (!deployText.contains(_deployCompletePhrase)) {
        throw StateError(
          'Не найдено финальное сообщение "$_deployCompletePhrase" в логе деплоя',
        );
      }

      final resolvedBootstrapEndpoint = await _resolveBootstrapEndpoint(
        normalizedHost,
        onProgress: onProgress,
      );
      final resolvedRelayEndpoint = await _resolveRelayEndpoint(
        normalizedHost,
        onProgress: onProgress,
      );

      try {
        await _verifyBootstrap(Uri.parse(resolvedBootstrapEndpoint));
        _emitStage(onProgress, 12, 'Test connection bootstrap (ok)');
      } catch (_) {
        _emitStage(onProgress, 12, 'Test connection bootstrap (fail)');
        rethrow;
      }

      try {
        await _verifyRelay(Uri.parse(resolvedRelayEndpoint));
        _emitStage(onProgress, 13, 'Test connection relay (ok)');
      } catch (_) {
        _emitStage(onProgress, 13, 'Test connection relay (fail)');
        rethrow;
      }

      try {
        await _verifyTurn(normalizedHost);
        _emitStage(onProgress, 14, 'Test connection turn (ok)');
      } catch (_) {
        _emitStage(onProgress, 14, 'Test connection turn (fail)');
        rethrow;
      }
      return SelfHostedDeployResult(
        host: normalizedHost,
        bootstrapEndpoint: resolvedBootstrapEndpoint,
        relayEndpoint: resolvedRelayEndpoint,
        turnServers: <TurnServerConfig>[
          TurnServerConfig(
            url: 'turns:$normalizedHost:5349?transport=tcp',
            username: turnUser,
            password: turnPassword,
            priority: 1000,
          ),
          TurnServerConfig(
            url: 'turn:$normalizedHost:3478?transport=udp',
            username: turnUser,
            password: turnPassword,
            priority: 500,
          ),
          TurnServerConfig(
            url: 'turn:$normalizedHost:3478?transport=tcp',
            username: turnUser,
            password: turnPassword,
            priority: 250,
          ),
        ],
      );
    } finally {
      client.close();
    }
  }

  String _buildDeployCommand({
    required String turnUser,
    required String turnPassword,
    required String loginPassword,
  }) {
    final escapedTurnUser = _shellEscape(turnUser);
    final escapedTurnPassword = _shellEscape(turnPassword);
    final escapedLoginPassword = _shellEscape(loginPassword);
    final escapedScriptUrl = _shellEscape(_bootstrapScriptUrl);
    final escapedRepoUrl = _shellEscape(_deployRepoUrl);
    final escapedBranch = _shellEscape(_deployBranch);
    final escapedDirName = _shellEscape(_deployDirName);

    final script = [
      'set -euo pipefail',
      'if command -v sudo >/dev/null 2>&1; then',
      '  printf %s $escapedLoginPassword | sudo -S -v',
      'fi',
      'export TURN_USER=$escapedTurnUser',
      'export TURN_PASSWORD=$escapedTurnPassword',
      'if [ -e $escapedDirName ]; then rm -rf $escapedDirName || true; fi',
      'if [ -e $escapedDirName ] && command -v sudo >/dev/null 2>&1; then sudo rm -rf $escapedDirName || true; fi',
      'if [ -e $escapedDirName ]; then echo "cleanup failed for $escapedDirName"; exit 1; fi',
      'rm -f get-docker.sh || true',
      'wget -qO- $escapedScriptUrl | bash -s -- $escapedRepoUrl $escapedBranch $escapedDirName',
      'echo $_deploySuccessMarker',
    ].join('\n');

    return "bash -lc ${_shellEscape(script)}";
  }

  Future<String> _runStreamingCommand({
    required SSHClient client,
    required String command,
    void Function(String message)? onProgress,
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
      if (_tryEmitStageMessage(clean, onProgress)) {
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
      (data) => consumeChunk(
        utf8.decode(data, allowMalformed: true),
        isError: false,
      ),
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
      (data) => consumeChunk(
        utf8.decode(data, allowMalformed: true),
        isError: true,
      ),
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
      throw StateError('Удаленная команда завершилась с exit code $exitCode');
    }

    return output.toString().trim();
  }

  Future<String> _resolveBootstrapEndpoint(
    String host, {
    void Function(String message)? onProgress,
  }) async {
    final candidate = 'wss://$host:443';
    await _verifyBootstrap(Uri.parse(candidate));
    _emitStage(onProgress, 12, 'bootstrap endpoint: $candidate');
    return candidate;
  }

  Future<String> _resolveRelayEndpoint(
    String host, {
    void Function(String message)? onProgress,
  }) async {
    final candidate = 'https://$host:444';
    await _verifyRelay(Uri.parse(candidate));
    _emitStage(onProgress, 13, 'relay endpoint: $candidate');
    return candidate;
  }

  Future<void> _verifyBootstrap(Uri endpoint) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (cert, host, port) => true;
    final ws = await WebSocket.connect(
      endpoint.toString(),
      customClient: client,
    ).timeout(
      const Duration(seconds: 8),
    );
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
    final socket = await SecureSocket.connect(
      host,
      5349,
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8),
    );
    socket.destroy();
  }

  String _normalizeHost(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return '';
    }
    if (!value.contains('://')) {
      value = 'ssh://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return input.trim();
    }
    if (uri.host.isNotEmpty) {
      return uri.host;
    }
    return input.trim();
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

  String _lastLines(String text, {int maxLines = 6}) {
    final lines = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '';
    }
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  String _shellEscape(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  bool _tryEmitStageMessage(
    String line,
    void Function(String message)? onProgress,
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
    _emitStage(onProgress, stage, text);
    return true;
  }

  void _emitStage(
    void Function(String message)? onProgress,
    int stage,
    String text,
  ) {
    _log(onProgress, 'Этап $stage/$_totalStages: $text');
  }

  void _log(void Function(String message)? sink, String message) {
    sink?.call(message);
  }
}
