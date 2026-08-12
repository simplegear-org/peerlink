class CallRemoteAudioMuteController {
  CallRemoteAudioMuteController({
    required void Function(String message) log,
    required void Function(bool value) setRemoteAudioMuted,
    required void Function(bool value) setRemoteAudioFlowSeen,
    required String Function() runtimeSnapshot,
  }) : _log = log,
       _setRemoteAudioMuted = setRemoteAudioMuted,
       _setRemoteAudioFlowSeen = setRemoteAudioFlowSeen,
       _runtimeSnapshot = runtimeSnapshot;

  final void Function(String message) _log;
  final void Function(bool value) _setRemoteAudioMuted;
  final void Function(bool value) _setRemoteAudioFlowSeen;
  final String Function() _runtimeSnapshot;

  int _version = -1;

  void handle({required bool muted, required int version}) {
    if (version <= _version) {
      _log(
        'audio:remote mute ignored muted=$muted version=$version '
        'lastVersion=$_version',
      );
      return;
    }
    _version = version;
    _setRemoteAudioMuted(muted);
    _setRemoteAudioFlowSeen(false);
    _log(
      'audio:remote mute state muted=$muted version=$version '
      'snapshot=${_runtimeSnapshot()}',
    );
  }
}
