import 'signaling_message.dart';

enum SignalingConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Контракт signaling-слоя для обмена SDP/ICE между peer.
abstract class SignalingService {
  /// Подключает signaling к выбранному серверу/каналу.
  Future<void> setServer(String endpoint);

  /// Подключает signaling сразу к нескольким серверам/каналам.
  Future<void> configureServers(List<String> endpoints);

  /// Отправляет произвольное signaling-сообщение удаленному peer.
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  );

  /// Отправляет offer удаленному peer.
  Future<void> sendOffer(
    String peerId,
    Map<String, dynamic> offer,
  );

  /// Отправляет answer удаленному peer.
  Future<void> sendAnswer(
    String peerId,
    Map<String, dynamic> answer,
  );

  /// Отправляет ICE candidate удаленному peer.
  Future<void> sendIce(
    String peerId,
    Map<String, dynamic> candidate,
  );

  /// Поток входящих signaling сообщений.
  Stream<SignalingMessage> get messages;

  /// Поток автоматически обнаруженных peerId.
  Stream<List<String>> get peersStream;

  /// Текущее состояние signaling-соединения.
  SignalingConnectionStatus get connectionStatus;

  /// Поток изменения состояния signaling-соединения.
  Stream<SignalingConnectionStatus> get connectionStatusStream;

  /// Последняя ошибка соединения (если есть).
  String? get lastError;

  /// Поток изменения последней ошибки.
  Stream<String?> get lastErrorStream;

  /// Закрывает signaling-соединение и освобождает ресурсы.
  Future<void> close();
}
