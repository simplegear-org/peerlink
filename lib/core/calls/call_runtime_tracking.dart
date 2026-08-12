import 'call_models.dart';
import 'call_state_update_helper.dart';

class CallRemoteAudioMuteSnapshot {
  final bool muted;
  final int version;

  const CallRemoteAudioMuteSnapshot({
    required this.muted,
    required this.version,
  });
}

class CallRemoteVideoStateSnapshot {
  final bool enabled;
  final int version;

  const CallRemoteVideoStateSnapshot({
    required this.enabled,
    required this.version,
  });
}

class CallRuntimeTracking {
  int _statsOffsetSent = 0;
  int _statsOffsetReceived = 0;
  int _lastPeerSentBytes = 0;
  int _lastPeerReceivedBytes = 0;
  int _localAudioMuteVersion = 0;
  bool _remoteAudioMuted = false;
  int _remoteAudioMuteVersion = -1;
  bool _remoteVideoEnabled = false;
  int _remoteVideoStateVersion = -1;
  DateTime? _lastMediaStatsAdvancedAt;

  void reset() {
    _statsOffsetSent = 0;
    _statsOffsetReceived = 0;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    _localAudioMuteVersion = 0;
    _remoteAudioMuted = false;
    _remoteAudioMuteVersion = -1;
    _remoteVideoEnabled = false;
    _remoteVideoStateVersion = -1;
    _lastMediaStatsAdvancedAt = null;
  }

  CallStatsUpdateResult applyPeerStats({
    required CallState currentState,
    required int sentBytes,
    required int receivedBytes,
    required CallStateUpdateHelper stateUpdateHelper,
    DateTime Function() now = DateTime.now,
  }) {
    final result = stateUpdateHelper.applyPeerStats(
      currentState: currentState,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
      statsOffsetSent: _statsOffsetSent,
      statsOffsetReceived: _statsOffsetReceived,
      lastPeerSentBytes: _lastPeerSentBytes,
      lastPeerReceivedBytes: _lastPeerReceivedBytes,
    );
    _statsOffsetSent = result.statsOffsetSent;
    _statsOffsetReceived = result.statsOffsetReceived;
    _lastPeerSentBytes = result.lastPeerSentBytes;
    _lastPeerReceivedBytes = result.lastPeerReceivedBytes;
    if (result.state.bytesSent != currentState.bytesSent ||
        result.state.bytesReceived != currentState.bytesReceived) {
      _lastMediaStatsAdvancedAt = now();
    }
    return result;
  }

  void resetPeerStatsTracking(CallState currentState) {
    _statsOffsetSent = currentState.bytesSent;
    _statsOffsetReceived = currentState.bytesReceived;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    _lastMediaStatsAdvancedAt = null;
  }

  bool isMediaRecentlyActive({
    required Duration grace,
    DateTime Function() now = DateTime.now,
  }) {
    final lastAdvancedAt = _lastMediaStatsAdvancedAt;
    if (lastAdvancedAt == null) {
      return false;
    }
    return now().difference(lastAdvancedAt) <= grace;
  }

  int nextLocalAudioMuteVersion() {
    _localAudioMuteVersion += 1;
    return _localAudioMuteVersion;
  }

  bool shouldApplyRemoteAudioMuteVersion(int version) {
    return version > _remoteAudioMuteVersion;
  }

  void applyRemoteAudioMute({required bool muted, required int version}) {
    _remoteAudioMuted = muted;
    _remoteAudioMuteVersion = version;
  }

  CallRemoteAudioMuteSnapshot? get remoteAudioMuteSnapshot {
    if (_remoteAudioMuteVersion < 0) {
      return null;
    }
    return CallRemoteAudioMuteSnapshot(
      muted: _remoteAudioMuted,
      version: _remoteAudioMuteVersion,
    );
  }

  int get remoteAudioMuteVersion => _remoteAudioMuteVersion;

  bool shouldApplyRemoteVideoStateVersion(int version) {
    return version > _remoteVideoStateVersion;
  }

  void applyRemoteVideoState({required bool enabled, required int version}) {
    _remoteVideoEnabled = enabled;
    _remoteVideoStateVersion = version;
  }

  CallRemoteVideoStateSnapshot? get remoteVideoStateSnapshot {
    if (_remoteVideoStateVersion < 0) {
      return null;
    }
    return CallRemoteVideoStateSnapshot(
      enabled: _remoteVideoEnabled,
      version: _remoteVideoStateVersion,
    );
  }

  int get remoteVideoStateVersion => _remoteVideoStateVersion;
}
