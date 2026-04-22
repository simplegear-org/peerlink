import 'dart:async';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'peer_session.dart';

/// Сообщение, полученное транспортным слоем от удаленного peer.
class TransportMessage {
  final String from;
  final Uint8List data;

  TransportMessage(this.from, this.data);
}

class TransportManager {
  final _controller = StreamController<TransportMessage>.broadcast();
  final Map<String, PeerSession> _sessions = {};

  /// Поток входящих транспортных сообщений для overlay/верхних слоев.
  Stream<TransportMessage> get onMessage => _controller.stream;

  /// Публикует входящее сообщение в транспортный event stream.
  void emit(String from, Uint8List data) {
    developer.log('[transport] recv from=$from bytes=${data.length}');
    _controller.add(TransportMessage(from, data));
  }

  /// Регистрирует активную peer-сессию в транспорт-менеджере.
  void registerSession(PeerSession session) {
    _sessions[session.peerId] = session;
  }

  /// Удаляет peer-сессию из транспорт-менеджера.
  void unregisterSession(String peerId) {
    _sessions.remove(peerId);
  }

  /// Отправляет данные через обязательный путь активной peer-сессии.
  Future<void> send(String peerId, Uint8List data) async {
    final session = _sessions[peerId];

    if (session == null) {
      developer.log('[transport] send failed: no session for $peerId');
      throw Exception('No transport session for $peerId');
    }

    try {
      developer.log('[transport] send to=$peerId bytes=${data.length}');
      await session.send(data);
    } catch (e) {
      developer.log('[transport] send failed: $e');
      rethrow;
    }
  }

  /// Закрывает внутренний stream транспорт-менеджера.
  void dispose() {
    _controller.close();
  }
}
