import 'transport_mode.dart';
import 'dart:typed_data';


abstract class Transport {
  TransportMode get mode;

  Future<void> connect(String peerId);
  Future<void> send(Uint8List data);
  Future<void> close();

  bool get isHealthy;
}