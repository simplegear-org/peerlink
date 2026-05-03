import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'transport.dart';
import 'transport_mode.dart';

/// Сессия прямого WebRTC-соединения с peer.
class PeerSession {
  final String peerId;
  final Transport direct;

  Transport? _active;
  TransportMode? _mode;
  Future<void>? _connectFuture;

  Timer? _healthTimer;
  int _logSeq = 0;

  PeerSession({
    required this.peerId,
    required this.direct,
  });

  /// Текущий активный режим транспорта.
  TransportMode? get currentMode => _mode;

  /// Поднимает соединение, начиная с direct транспорта.
  Future<void> connect() async {
    if (_connectFuture != null) {
      await _connectFuture;
      return;
    }

    _connectFuture = _connectInternal();
    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  /// Отправляет данные через текущий активный транспорт.
  Future<void> send(Uint8List data) async {
    if (_active == null) {
      _log('send:wait active transport');
      await connect();
    }

    final transport = _active;
    if (transport == null) {
      _log('send:drop no active transport');
      throw Exception('No active transport');
    }

    _log('send bytes=${data.length} mode=${transport.mode.name}');
    await transport.send(data);
  }

  /// Закрывает активный транспорт и мониторинг здоровья.
  Future<void> close() async {
    _healthTimer?.cancel();
    await _active?.close();
  }

  // =========================
  // PRIVATE
  // =========================

  /// Пробует прямой транспорт.
  Future<void> _tryDirect() async {
    try {
      _log('tryDirect:start');
      await direct.connect(peerId);
      _activate(direct);
      _log('tryDirect:connected');
    } catch (e) {
      _log('tryDirect:failed error=$e');
      _active = null;
      _mode = null;
    }
  }

  Future<void> _connectInternal() async {
    _log('connect:start');
    await _tryDirect();
    _startHealthMonitor();
  }

  /// Переключает активный транспорт в сессии.
  void _activate(Transport transport) {
    _active = transport;
    _mode = transport.mode;
  }

  /// Запускает периодическую проверку состояния канала.
  void _startHealthMonitor() {
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_active == null) return;

      if (!_active!.isHealthy) {
        await _failover();
      }
    });
  }

  /// Выполняет failover при деградации активного канала.
  Future<void> _failover() async {
    await _active?.close();
    _active = null;
    _mode = null;
  }

  void _log(String message) {
    developer.log('[session][$peerId][${_logSeq++}] $message');
  }
}
