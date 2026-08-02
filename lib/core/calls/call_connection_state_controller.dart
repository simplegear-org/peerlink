import '../transport/transport_mode.dart';

class CallConnectionStateController {
  final void Function(String message) _log;
  final TransportMode? Function() _getMode;
  final bool Function() _getConnected;
  final void Function(bool value) _setConnected;
  final bool Function() _getIceConnected;
  final bool Function() _getRemoteTrackSeen;
  final bool Function() _getRemoteAudioFlowSeen;
  final void Function(TransportMode mode) _onConnected;
  final void Function() _armMediaFlowFallback;

  const CallConnectionStateController({
    required void Function(String message) log,
    required TransportMode? Function() getMode,
    required bool Function() getConnected,
    required void Function(bool value) setConnected,
    required bool Function() getIceConnected,
    required bool Function() getRemoteTrackSeen,
    required bool Function() getRemoteAudioFlowSeen,
    required void Function(TransportMode mode) onConnected,
    required void Function() armMediaFlowFallback,
  }) : _log = log,
       _getMode = getMode,
       _getConnected = getConnected,
       _setConnected = setConnected,
       _getIceConnected = getIceConnected,
       _getRemoteTrackSeen = getRemoteTrackSeen,
       _getRemoteAudioFlowSeen = getRemoteAudioFlowSeen,
       _onConnected = onConnected,
       _armMediaFlowFallback = armMediaFlowFallback;

  void notifyConnected() {
    final mode = _getMode();
    if (_getConnected() || mode == null) {
      return;
    }
    if (!_getIceConnected() || !_getRemoteTrackSeen()) {
      _log(
        'connected:waiting ice=${_getIceConnected()} '
        'remoteTrack=${_getRemoteTrackSeen()} '
        'audioFlow=${_getRemoteAudioFlowSeen()}',
      );
      return;
    }
    _setConnected(true);
    _log(
      'connected transportReady=true '
      'remoteTrackSeen=${_getRemoteTrackSeen()} '
      'audioFlow=${_getRemoteAudioFlowSeen()}',
    );
    _onConnected(mode);
    _armMediaFlowFallback();
  }
}
