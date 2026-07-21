import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import 'call_media_stats_utils.dart';

typedef CallVideoNetworkStatsHandler =
    Future<void> Function({
      required AudioTrafficStats stats,
      required double outboundKbps,
    });

typedef CallRecoveryStatsHandler = void Function(AudioTrafficStats stats);

class CallMediaFlowController {
  static const String iceReconnectStalledReason =
      'ICE did not reconnect after recovery signaling';

  static const Duration _postIceRecoveryFlowGrace = Duration(seconds: 4);
  static const Duration _statsPollInterval = Duration(seconds: 1);
  static const Duration _videoWaitLogThrottle = Duration(seconds: 4);
  static const Duration _mediaDiagnosticsLogThrottle = Duration(seconds: 5);
  static const Duration _stallWarningThrottle = Duration(seconds: 5);
  static const int _liveMediaStallThresholdPolls = 12;
  static const int _stallSuspectThresholdPolls = 3;
  static const int _localAudioOutboundStallThresholdPolls = 5;
  static const Duration _liveMediaStallCooldown = Duration(seconds: 12);
  static const Duration _localAudioOutboundStallCooldown = Duration(
    seconds: 12,
  );

  final SignalingService _signaling;
  final void Function(String message) _log;
  final RTCPeerConnection? Function() _getPeer;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final bool Function() _getIceConnected;
  final bool Function() _getIceRecoveryInProgress;
  final bool Function() _getLocalAudioMuted;
  final bool Function() _getRemoteAudioMuted;
  final bool Function() _getRemoteAudioTrackSeen;
  final bool Function() _getRemoteVideoTrackSeen;
  final bool Function() _getRemoteAudioFlowSeen;
  final void Function(bool value) _setRemoteAudioFlowSeen;
  final bool Function() _getRemoteVideoEnabled;
  final bool Function() _getRemoteVideoFlowSeen;
  final void Function(bool value) _setRemoteVideoFlowSeen;
  final void Function() _markRemoteVideoFlowDetected;
  final int? Function() _getPendingRemoteVideoFlowAckVersion;
  final void Function(int? value) _setPendingRemoteVideoFlowAckVersion;
  final bool Function() _getMediaFlowNotified;
  final void Function(bool value) _setMediaFlowNotified;
  final void Function() _notifyConnected;
  final Future<void> Function() _onMediaFlow;
  final void Function(bool active) _onRemoteVideoFlowChanged;
  final void Function() _onIceMediaRecoveryCompleted;
  final Future<void> Function(String reason) _onIceReconnectStalled;
  final Future<void> Function(String reason) _onPostIceRecoveryFlowStalled;
  final Future<void> Function(String reason)?
  _onPostIceRecoveryVideoOnlyStalled;
  final Future<void> Function(String reason) _onLiveMediaFlowStalled;
  final Future<void> Function(String reason)? _onLocalAudioOutboundStalled;
  final void Function({required int sentBytes, required int receivedBytes})
  _onStats;
  final CallRecoveryStatsHandler? _onRecoveryStats;
  final int Function() _getSessionEpoch;
  final CallVideoNetworkStatsHandler? _onVideoNetworkStats;

  Timer? _audioStatsTimer;
  Timer? _mediaFlowFallbackTimer;
  Timer? _postIceRecoveryFlowTimer;
  int _postIceRecoveryFlowGeneration = 0;
  int _lastInboundBytes = -1;
  int _lastInboundPackets = -1;
  double _lastInboundAudioEnergy = -1;
  double _lastInboundSamplesDuration = -1;
  int _lastInboundVideoBytes = -1;
  int _lastInboundVideoFramesDecoded = -1;
  int _lastLiveInboundBytes = -1;
  int _lastLiveInboundPackets = -1;
  int _lastLiveOutboundBytes = -1;
  int _lastLiveInboundVideoBytes = -1;
  int _lastLiveInboundVideoFramesDecoded = -1;
  int _reportedSentBytes = 0;
  int _reportedReceivedBytes = 0;
  int _lastVideoNetworkSentBytes = -1;
  DateTime? _lastVideoNetworkStatsAt;
  bool _awaitingPostIceRecoveryFlow = false;
  bool _expectRemoteVideoRecovery = false;
  DateTime? _lastVideoWaitingLogAt;
  DateTime? _lastMediaDiagnosticsLogAt;
  String? _lastMediaPathSignature;
  int _consecutiveInboundStallPolls = 0;
  int _consecutiveOutboundStallPolls = 0;
  int _consecutiveVideoInboundStallPolls = 0;
  DateTime? _lastLiveMediaStallAt;
  DateTime? _lastLocalAudioOutboundStallAt;
  DateTime? _lastInboundStallWarningAt;
  DateTime? _lastVideoInboundStallWarningAt;
  DateTime? _lastExpectedAudioSilenceLogAt;
  DateTime? _lastExpectedVideoSilenceLogAt;

  CallMediaFlowController({
    required SignalingService signaling,
    required void Function(String message) log,
    required RTCPeerConnection? Function() getPeer,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required bool Function() getIceConnected,
    required bool Function() getIceRecoveryInProgress,
    bool Function()? getLocalAudioMuted,
    bool Function()? getRemoteAudioMuted,
    required bool Function() getRemoteAudioTrackSeen,
    required bool Function() getRemoteVideoTrackSeen,
    required bool Function() getRemoteAudioFlowSeen,
    required void Function(bool value) setRemoteAudioFlowSeen,
    required bool Function() getRemoteVideoEnabled,
    required bool Function() getRemoteVideoFlowSeen,
    required void Function(bool value) setRemoteVideoFlowSeen,
    required void Function() markRemoteVideoFlowDetected,
    required int? Function() getPendingRemoteVideoFlowAckVersion,
    required void Function(int? value) setPendingRemoteVideoFlowAckVersion,
    required bool Function() getMediaFlowNotified,
    required void Function(bool value) setMediaFlowNotified,
    required void Function() notifyConnected,
    required Future<void> Function() onMediaFlow,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required void Function() onIceMediaRecoveryCompleted,
    required Future<void> Function(String reason) onIceReconnectStalled,
    required Future<void> Function(String reason) onPostIceRecoveryFlowStalled,
    Future<void> Function(String reason)? onPostIceRecoveryVideoOnlyStalled,
    required Future<void> Function(String reason) onLiveMediaFlowStalled,
    Future<void> Function(String reason)? onLocalAudioOutboundStalled,
    required void Function({required int sentBytes, required int receivedBytes})
    onStats,
    CallRecoveryStatsHandler? onRecoveryStats,
    required int Function() getSessionEpoch,
    CallVideoNetworkStatsHandler? onVideoNetworkStats,
  }) : _signaling = signaling,
       _log = log,
       _getPeer = getPeer,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _getIceConnected = getIceConnected,
       _getIceRecoveryInProgress = getIceRecoveryInProgress,
       _getLocalAudioMuted = getLocalAudioMuted ?? (() => false),
       _getRemoteAudioMuted = getRemoteAudioMuted ?? (() => false),
       _getRemoteAudioTrackSeen = getRemoteAudioTrackSeen,
       _getRemoteVideoTrackSeen = getRemoteVideoTrackSeen,
       _getRemoteAudioFlowSeen = getRemoteAudioFlowSeen,
       _setRemoteAudioFlowSeen = setRemoteAudioFlowSeen,
       _getRemoteVideoEnabled = getRemoteVideoEnabled,
       _getRemoteVideoFlowSeen = getRemoteVideoFlowSeen,
       _setRemoteVideoFlowSeen = setRemoteVideoFlowSeen,
       _markRemoteVideoFlowDetected = markRemoteVideoFlowDetected,
       _getPendingRemoteVideoFlowAckVersion =
           getPendingRemoteVideoFlowAckVersion,
       _setPendingRemoteVideoFlowAckVersion =
           setPendingRemoteVideoFlowAckVersion,
       _getMediaFlowNotified = getMediaFlowNotified,
       _setMediaFlowNotified = setMediaFlowNotified,
       _notifyConnected = notifyConnected,
       _onMediaFlow = onMediaFlow,
       _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
       _onIceMediaRecoveryCompleted = onIceMediaRecoveryCompleted,
       _onIceReconnectStalled = onIceReconnectStalled,
       _onPostIceRecoveryFlowStalled = onPostIceRecoveryFlowStalled,
       _onPostIceRecoveryVideoOnlyStalled = onPostIceRecoveryVideoOnlyStalled,
       _onLiveMediaFlowStalled = onLiveMediaFlowStalled,
       _onLocalAudioOutboundStalled = onLocalAudioOutboundStalled,
       _onStats = onStats,
       _onRecoveryStats = onRecoveryStats,
       _getSessionEpoch = getSessionEpoch,
       _onVideoNetworkStats = onVideoNetworkStats;

  void ensureAudioStatsPolling() {
    if (_audioStatsTimer?.isActive ?? false) {
      return;
    }
    final expectedEpoch = _getSessionEpoch();
    _audioStatsTimer = Timer.periodic(
      _statsPollInterval,
      (_) => unawaited(_pollInboundAudioStats(expectedEpoch)),
    );
    unawaited(_pollInboundAudioStats(expectedEpoch));
  }

  void stopAudioStatsPolling() {
    _audioStatsTimer?.cancel();
    _audioStatsTimer = null;
    cancelMediaFlowFallback();
    _lastInboundBytes = -1;
    _lastInboundPackets = -1;
    _lastInboundAudioEnergy = -1;
    _lastInboundSamplesDuration = -1;
    _lastInboundVideoBytes = -1;
    _lastInboundVideoFramesDecoded = -1;
    _lastLiveInboundBytes = -1;
    _lastLiveInboundPackets = -1;
    _lastLiveOutboundBytes = -1;
    _lastLiveInboundVideoBytes = -1;
    _lastLiveInboundVideoFramesDecoded = -1;
    _reportedSentBytes = 0;
    _reportedReceivedBytes = 0;
    _lastVideoNetworkSentBytes = -1;
    _lastVideoNetworkStatsAt = null;
    _awaitingPostIceRecoveryFlow = false;
    _expectRemoteVideoRecovery = false;
    _lastVideoWaitingLogAt = null;
    _lastMediaDiagnosticsLogAt = null;
    _lastMediaPathSignature = null;
    _consecutiveInboundStallPolls = 0;
    _consecutiveOutboundStallPolls = 0;
    _consecutiveVideoInboundStallPolls = 0;
    _lastLiveMediaStallAt = null;
    _lastLocalAudioOutboundStallAt = null;
    _lastInboundStallWarningAt = null;
    _lastVideoInboundStallWarningAt = null;
    _lastExpectedAudioSilenceLogAt = null;
    _lastExpectedVideoSilenceLogAt = null;
    _clearPostIceRecoveryFlowWatch();
  }

  void beginIceRecoveryFlowWatch() {
    final expectVideo =
        _getRemoteVideoEnabled() &&
        (_getRemoteVideoTrackSeen() || _getRemoteVideoFlowSeen());
    _awaitingPostIceRecoveryFlow = true;
    _expectRemoteVideoRecovery = expectVideo;
    _setRemoteAudioFlowSeen(false);
    if (_getRemoteVideoFlowSeen()) {
      _setRemoteVideoFlowSeen(false);
      _onRemoteVideoFlowChanged(false);
    }
    _lastInboundBytes = -1;
    _lastInboundPackets = -1;
    _lastInboundAudioEnergy = -1;
    _lastInboundSamplesDuration = -1;
    _lastInboundVideoBytes = -1;
    _lastInboundVideoFramesDecoded = -1;
    _lastLiveInboundBytes = -1;
    _lastLiveInboundPackets = -1;
    _lastLiveOutboundBytes = -1;
    _lastLiveInboundVideoBytes = -1;
    _lastLiveInboundVideoFramesDecoded = -1;
    _consecutiveVideoInboundStallPolls = 0;
    _invalidatePostIceRecoveryFlowTimer();
    _log('ice:media watch start expectVideo=$expectVideo');
  }

  void resetPostIceRecoveryFlowWatch({required String reason}) {
    if (!_awaitingPostIceRecoveryFlow &&
        !(_postIceRecoveryFlowTimer?.isActive ?? false)) {
      return;
    }
    _invalidatePostIceRecoveryFlowTimer();
    _log('ice:media watch reset reason="$reason"');
  }

  void armPostIceRecoveryFlowWatch() {
    if (!_awaitingPostIceRecoveryFlow ||
        _getPeer() == null ||
        (_postIceRecoveryFlowTimer?.isActive ?? false)) {
      return;
    }
    final expectedEpoch = _getSessionEpoch();
    final expectedGeneration = _postIceRecoveryFlowGeneration;
    _postIceRecoveryFlowTimer = Timer(_postIceRecoveryFlowGrace, () async {
      _postIceRecoveryFlowTimer = null;
      if (!_isCurrentPostIceRecoveryWatch(
        expectedEpoch: expectedEpoch,
        expectedGeneration: expectedGeneration,
      )) {
        return;
      }
      if (!_getIceConnected()) {
        if (_getIceRecoveryInProgress()) {
          _log('ice:reconnect watch pending recovery');
          return;
        }
        _log('ice:reconnect watch timeout');
        await _onIceReconnectStalled(iceReconnectStalledReason);
        return;
      }
      final missingAudio =
          !_getRemoteAudioMuted() && !_getRemoteAudioFlowSeen();
      final missingVideo =
          _expectRemoteVideoRecovery && !_getRemoteVideoFlowSeen();
      if (!missingAudio && !missingVideo) {
        return;
      }
      _log(
        'ice:media watch timeout missingAudio=$missingAudio '
        'missingVideo=$missingVideo expectVideo=$_expectRemoteVideoRecovery',
      );
      if (!missingAudio && missingVideo) {
        final handler = _onPostIceRecoveryVideoOnlyStalled;
        if (handler != null) {
          _postIceRecoveryFlowGeneration += 1;
          _awaitingPostIceRecoveryFlow = false;
          _expectRemoteVideoRecovery = false;
          _onRemoteVideoFlowChanged(false);
          await handler(
            'Remote video flow did not recover after ICE reconnection',
          );
          if (_getIceRecoveryInProgress()) {
            _log('ice:media recovered audioOnly=true');
            _onIceMediaRecoveryCompleted();
          }
          return;
        }
      }
      await _onPostIceRecoveryFlowStalled(
        'Media flow did not recover after ICE reconnection',
      );
    });
    _log(
      'ice:media watch armed graceMs=${_postIceRecoveryFlowGrace.inMilliseconds}',
    );
  }

  void armMediaFlowFallback() {
    if (_getMediaFlowNotified() ||
        !_getIceConnected() ||
        !_getRemoteAudioTrackSeen() ||
        _getPeer() == null) {
      return;
    }
    if (_mediaFlowFallbackTimer?.isActive ?? false) {
      return;
    }
    final expectedEpoch = _getSessionEpoch();
    _mediaFlowFallbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (_getSessionEpoch() != expectedEpoch) {
        _mediaFlowFallbackTimer = null;
        return;
      }
      _mediaFlowFallbackTimer = null;
      if (_getMediaFlowNotified() ||
          !_getIceConnected() ||
          !_getRemoteAudioTrackSeen() ||
          _getPeer() == null) {
        return;
      }
      _setRemoteAudioFlowSeen(true);
      _setMediaFlowNotified(true);
      _log(
        'audio:flow fallback transportReady=${_getIceConnected()} '
        'remoteAudioTrackSeen=${_getRemoteAudioTrackSeen()}',
      );
      unawaited(_onMediaFlow());
      _notifyConnected();
    });
  }

  void cancelMediaFlowFallback() {
    _mediaFlowFallbackTimer?.cancel();
    _mediaFlowFallbackTimer = null;
  }

  Future<void> _pollInboundAudioStats(int expectedEpoch) async {
    if (_getSessionEpoch() != expectedEpoch) {
      return;
    }
    final peer = _getPeer();
    if (peer == null) {
      return;
    }
    try {
      final reports = await peer.getStats();
      if (_getSessionEpoch() != expectedEpoch || !identical(_getPeer(), peer)) {
        return;
      }
      final stats = extractAudioTrafficStats(reports);
      _logMediaDiagnostics(stats);
      _onRecoveryStats?.call(stats);
      _reportVideoNetworkStats(stats);
      if (stats.sentBytes != _reportedSentBytes ||
          stats.receivedBytes != _reportedReceivedBytes) {
        _reportedSentBytes = stats.sentBytes;
        _reportedReceivedBytes = stats.receivedBytes;
        _onStats(
          sentBytes: stats.sentBytes,
          receivedBytes: stats.receivedBytes,
        );
      }
      if (!_getRemoteAudioFlowSeen() && _detectInboundAudioFlow(stats)) {
        _setRemoteAudioFlowSeen(true);
        cancelMediaFlowFallback();
        _log('audio:flow detected');
        _completeIceRecoveryFlowIfReady();
        if (!_getMediaFlowNotified()) {
          _setMediaFlowNotified(true);
          unawaited(_onMediaFlow());
        }
        _notifyConnected();
      }
      if (_getRemoteVideoEnabled() &&
          !_getRemoteVideoFlowSeen() &&
          _detectInboundVideoFlow(stats)) {
        _setRemoteVideoFlowSeen(true);
        _markRemoteVideoFlowDetected();
        _log(
          'video:flow detected remoteTrackSeen=${_getRemoteVideoTrackSeen()}',
        );
        _onRemoteVideoFlowChanged(true);
        _completeIceRecoveryFlowIfReady();
        final version = _getPendingRemoteVideoFlowAckVersion();
        final peerId = _getPeerId();
        final callId = _getCallId();
        if (version != null && peerId != null && callId != null) {
          unawaited(
            _signaling.sendSignal(peerId, 'call_video_flow_ack', {
              'callId': callId,
              'signalScope': 'call',
              'version': version,
            }),
          );
          _log('video:flow ack sent version=$version');
          _setPendingRemoteVideoFlowAckVersion(null);
        }
      } else if (_getRemoteVideoEnabled() && _getRemoteVideoTrackSeen()) {
        final now = DateTime.now();
        final lastLogAt = _lastVideoWaitingLogAt;
        if (lastLogAt == null ||
            now.difference(lastLogAt) >= _videoWaitLogThrottle) {
          _lastVideoWaitingLogAt = now;
          _log(
            'video:flow waiting trackSeen=true '
            'videoBytes=${stats.videoBytesReceived} '
            'lastVideoBytes=$_lastInboundVideoBytes '
            'videoFrames=${stats.videoFramesDecoded} '
            'lastVideoFrames=$_lastInboundVideoFramesDecoded',
          );
        }
      }
      _evaluateLiveMediaStall(stats);
    } catch (error) {
      _log('audio:stats poll error=$error');
    }
  }

  bool _detectInboundAudioFlow(AudioTrafficStats stats) {
    final detected = detectInboundAudioFlow(
      stats: stats,
      lastInboundBytes: _lastInboundBytes,
      lastInboundPackets: _lastInboundPackets,
      lastInboundAudioEnergy: _lastInboundAudioEnergy,
      lastInboundSamplesDuration: _lastInboundSamplesDuration,
    );
    _lastInboundBytes = stats.receivedBytes;
    _lastInboundPackets = stats.packetsReceived;
    _lastInboundAudioEnergy = stats.totalAudioEnergy;
    _lastInboundSamplesDuration = stats.totalSamplesDuration;
    return detected;
  }

  bool _detectInboundVideoFlow(AudioTrafficStats stats) {
    final detected = detectInboundVideoFlow(
      stats: stats,
      lastInboundVideoBytes: _lastInboundVideoBytes,
      lastInboundVideoFramesDecoded: _lastInboundVideoFramesDecoded,
    );
    _lastInboundVideoBytes = stats.videoBytesReceived;
    _lastInboundVideoFramesDecoded = stats.videoFramesDecoded;
    return detected;
  }

  void _completeIceRecoveryFlowIfReady() {
    if (!_awaitingPostIceRecoveryFlow) {
      return;
    }
    final audioRecovered = _getRemoteAudioMuted() || _getRemoteAudioFlowSeen();
    final videoRecovered =
        !_expectRemoteVideoRecovery || _getRemoteVideoFlowSeen();
    if (!audioRecovered || !videoRecovered) {
      return;
    }
    _awaitingPostIceRecoveryFlow = false;
    _expectRemoteVideoRecovery = false;
    _invalidatePostIceRecoveryFlowTimer();
    if (_getIceRecoveryInProgress()) {
      _log('ice:media recovered');
      _onIceMediaRecoveryCompleted();
    }
  }

  void _evaluateLiveMediaStall(AudioTrafficStats stats) {
    if (!_getMediaFlowNotified() ||
        !_getIceConnected() ||
        _getIceRecoveryInProgress() ||
        _getPeer() == null ||
        !_getRemoteAudioTrackSeen()) {
      _consecutiveInboundStallPolls = 0;
      _consecutiveOutboundStallPolls = 0;
      _consecutiveVideoInboundStallPolls = 0;
      _resetLiveMediaBaseline();
      return;
    }
    final previousLiveInboundBytes = _lastLiveInboundBytes;
    final previousLiveInboundPackets = _lastLiveInboundPackets;
    final previousLiveOutboundBytes = _lastLiveOutboundBytes;
    final previousLiveInboundVideoBytes = _lastLiveInboundVideoBytes;
    final previousLiveInboundVideoFrames = _lastLiveInboundVideoFramesDecoded;
    final remoteAudioMuted = _getRemoteAudioMuted();
    final bytesAdvanced = previousLiveInboundBytes >= 0
        ? stats.receivedBytes > previousLiveInboundBytes
        : true;
    final packetsAdvanced = previousLiveInboundPackets >= 0
        ? stats.packetsReceived > previousLiveInboundPackets
        : true;
    final outboundAdvanced = previousLiveOutboundBytes >= 0
        ? stats.audioSentBytes > previousLiveOutboundBytes
        : true;
    final remoteVideoEnabled = _getRemoteVideoEnabled();
    final videoExpected =
        remoteVideoEnabled &&
        (_getRemoteVideoTrackSeen() || _getRemoteVideoFlowSeen());
    final videoAdvanced =
        !videoExpected ||
        previousLiveInboundVideoBytes < 0 ||
        previousLiveInboundVideoFrames < 0 ||
        stats.videoBytesReceived > previousLiveInboundVideoBytes ||
        stats.videoFramesDecoded > previousLiveInboundVideoFrames;
    _updateLiveMediaBaseline(stats);
    if (remoteAudioMuted && !bytesAdvanced && !packetsAdvanced) {
      _logExpectedAudioSilence(source: 'remote-muted', stats: stats);
    }
    if (!remoteVideoEnabled &&
        (previousLiveInboundVideoBytes > 0 ||
            previousLiveInboundVideoFrames > 0) &&
        stats.videoBytesReceived <= previousLiveInboundVideoBytes &&
        stats.videoFramesDecoded <= previousLiveInboundVideoFrames) {
      _logExpectedVideoSilence(source: 'remote-disabled', stats: stats);
    }
    final audioOrTransportAdvanced =
        remoteAudioMuted || bytesAdvanced || packetsAdvanced;
    _evaluateLocalAudioOutboundStall(
      stats: stats,
      inboundAdvanced: audioOrTransportAdvanced,
      outboundAdvanced: outboundAdvanced,
      previousLiveOutboundBytes: previousLiveOutboundBytes,
    );
    _evaluateVideoInboundStall(
      stats: stats,
      audioOrTransportAdvanced: audioOrTransportAdvanced,
      videoExpected: videoExpected,
      videoAdvanced: videoAdvanced,
      previousLiveInboundVideoBytes: previousLiveInboundVideoBytes,
      previousLiveInboundVideoFrames: previousLiveInboundVideoFrames,
    );
    if (audioOrTransportAdvanced || (videoExpected && videoAdvanced)) {
      _consecutiveInboundStallPolls = 0;
      return;
    }
    _consecutiveInboundStallPolls += 1;
    if (_consecutiveInboundStallPolls < _liveMediaStallThresholdPolls) {
      if (_consecutiveInboundStallPolls >= _stallSuspectThresholdPolls) {
        _logInboundStallWarning(
          stats: stats,
          previousLiveInboundBytes: previousLiveInboundBytes,
          previousLiveInboundPackets: previousLiveInboundPackets,
          previousLiveOutboundBytes: previousLiveOutboundBytes,
          outboundAdvanced: outboundAdvanced,
        );
      }
      return;
    }
    final now = DateTime.now();
    final lastStallAt = _lastLiveMediaStallAt;
    if (lastStallAt != null &&
        now.difference(lastStallAt) < _liveMediaStallCooldown) {
      return;
    }
    _lastLiveMediaStallAt = now;
    _consecutiveInboundStallPolls = 0;
    if (outboundAdvanced) {
      _log(
        'diagnostic:warning freeze cause=inbound-only-stall '
        'action=no-ice-restart inboundStallPolls=$_liveMediaStallThresholdPolls '
        '${_buildMediaDiagnosticsMessage(stats)} '
        'audioDelta=${_delta(stats.receivedBytes, previousLiveInboundBytes)} '
        'packetDelta=${_delta(stats.packetsReceived, previousLiveInboundPackets)} '
        'audioOutDelta=${_delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
      );
      return;
    }
    _log(
      'diagnostic:warning freeze cause=full-media-stall action=diagnostic-only '
      'stallPolls=$_liveMediaStallThresholdPolls '
      '${_buildMediaDiagnosticsMessage(stats)} '
      'audioDelta=${_delta(stats.receivedBytes, previousLiveInboundBytes)} '
      'packetDelta=${_delta(stats.packetsReceived, previousLiveInboundPackets)} '
      'audioOutDelta=${_delta(stats.audioSentBytes, previousLiveOutboundBytes)} '
      'videoDelta=${_delta(stats.videoBytesReceived, previousLiveInboundVideoBytes)} '
      'frameDelta=${_delta(stats.videoFramesDecoded, previousLiveInboundVideoFrames)}',
    );
    unawaited(
      _onLiveMediaFlowStalled(
        'Live media stalled while ICE remained connected',
      ),
    );
  }

  void _evaluateLocalAudioOutboundStall({
    required AudioTrafficStats stats,
    required bool inboundAdvanced,
    required bool outboundAdvanced,
    required int previousLiveOutboundBytes,
  }) {
    final handler = _onLocalAudioOutboundStalled;
    if (handler == null) {
      return;
    }
    if (_getLocalAudioMuted()) {
      if (!outboundAdvanced &&
          inboundAdvanced &&
          previousLiveOutboundBytes >= 0) {
        _logExpectedAudioSilence(source: 'local-muted', stats: stats);
      }
      _consecutiveOutboundStallPolls = 0;
      return;
    }
    if (outboundAdvanced || !inboundAdvanced || previousLiveOutboundBytes < 0) {
      _consecutiveOutboundStallPolls = 0;
      return;
    }
    _consecutiveOutboundStallPolls += 1;
    if (_consecutiveOutboundStallPolls <
        _localAudioOutboundStallThresholdPolls) {
      return;
    }
    final now = DateTime.now();
    final lastStallAt = _lastLocalAudioOutboundStallAt;
    if (lastStallAt != null &&
        now.difference(lastStallAt) < _localAudioOutboundStallCooldown) {
      return;
    }
    _lastLocalAudioOutboundStallAt = now;
    _consecutiveOutboundStallPolls = 0;
    _log(
      'diagnostic:warning freeze cause=local-audio-outbound-stall '
      'action=refresh-audio-sender outboundStallPolls=$_localAudioOutboundStallThresholdPolls '
      '${_buildMediaDiagnosticsMessage(stats)} '
      'audioOutDelta=${_delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
    );
    unawaited(
      handler('Local audio outbound stalled while inbound media continued'),
    );
  }

  void _logExpectedAudioSilence({
    required String source,
    required AudioTrafficStats stats,
  }) {
    final now = DateTime.now();
    final lastLogAt = _lastExpectedAudioSilenceLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _stallWarningThrottle) {
      return;
    }
    _lastExpectedAudioSilenceLogAt = now;
    _log(
      'diagnostic:audio expected-silence source=$source '
      '${_buildMediaDiagnosticsMessage(stats)}',
    );
  }

  void _logExpectedVideoSilence({
    required String source,
    required AudioTrafficStats stats,
  }) {
    final now = DateTime.now();
    final lastLogAt = _lastExpectedVideoSilenceLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _stallWarningThrottle) {
      return;
    }
    _lastExpectedVideoSilenceLogAt = now;
    _log(
      'diagnostic:video expected-silence source=$source '
      '${_buildMediaDiagnosticsMessage(stats)}',
    );
  }

  void _evaluateVideoInboundStall({
    required AudioTrafficStats stats,
    required bool audioOrTransportAdvanced,
    required bool videoExpected,
    required bool videoAdvanced,
    required int previousLiveInboundVideoBytes,
    required int previousLiveInboundVideoFrames,
  }) {
    if (!videoExpected || videoAdvanced) {
      _consecutiveVideoInboundStallPolls = 0;
      return;
    }
    _consecutiveVideoInboundStallPolls += 1;
    if (!audioOrTransportAdvanced ||
        _consecutiveVideoInboundStallPolls < _stallSuspectThresholdPolls) {
      return;
    }
    final now = DateTime.now();
    final lastWarningAt = _lastVideoInboundStallWarningAt;
    if (lastWarningAt != null &&
        now.difference(lastWarningAt) < _stallWarningThrottle) {
      return;
    }
    _lastVideoInboundStallWarningAt = now;
    _log(
      'diagnostic:warning freeze-suspect cause=video-inbound-stall '
      'action=keep-audio-live videoStallPolls=$_consecutiveVideoInboundStallPolls '
      '${_buildMediaDiagnosticsMessage(stats)} '
      'videoDelta=${_delta(stats.videoBytesReceived, previousLiveInboundVideoBytes)} '
      'frameDelta=${_delta(stats.videoFramesDecoded, previousLiveInboundVideoFrames)}',
    );
  }

  void _logInboundStallWarning({
    required AudioTrafficStats stats,
    required int previousLiveInboundBytes,
    required int previousLiveInboundPackets,
    required int previousLiveOutboundBytes,
    required bool outboundAdvanced,
  }) {
    final now = DateTime.now();
    final lastWarningAt = _lastInboundStallWarningAt;
    if (lastWarningAt != null &&
        now.difference(lastWarningAt) < _stallWarningThrottle) {
      return;
    }
    _lastInboundStallWarningAt = now;
    _log(
      'diagnostic:warning freeze-suspect cause=inbound-audio-stall '
      'outboundAdvanced=$outboundAdvanced '
      'inboundStallPolls=$_consecutiveInboundStallPolls '
      '${_buildMediaDiagnosticsMessage(stats)} '
      'audioDelta=${_delta(stats.receivedBytes, previousLiveInboundBytes)} '
      'packetDelta=${_delta(stats.packetsReceived, previousLiveInboundPackets)} '
      'audioOutDelta=${_delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
    );
  }

  void _updateLiveMediaBaseline(AudioTrafficStats stats) {
    _lastLiveInboundBytes = stats.receivedBytes;
    _lastLiveInboundPackets = stats.packetsReceived;
    _lastLiveOutboundBytes = stats.audioSentBytes;
    _lastLiveInboundVideoBytes = stats.videoBytesReceived;
    _lastLiveInboundVideoFramesDecoded = stats.videoFramesDecoded;
  }

  void _resetLiveMediaBaseline() {
    _lastLiveInboundBytes = -1;
    _lastLiveInboundPackets = -1;
    _lastLiveOutboundBytes = -1;
    _lastLiveInboundVideoBytes = -1;
    _lastLiveInboundVideoFramesDecoded = -1;
  }

  void _cancelPostIceRecoveryFlowTimer() {
    _postIceRecoveryFlowTimer?.cancel();
    _postIceRecoveryFlowTimer = null;
  }

  void _invalidatePostIceRecoveryFlowTimer() {
    _postIceRecoveryFlowGeneration += 1;
    _cancelPostIceRecoveryFlowTimer();
  }

  void _clearPostIceRecoveryFlowWatch() {
    _awaitingPostIceRecoveryFlow = false;
    _expectRemoteVideoRecovery = false;
    _invalidatePostIceRecoveryFlowTimer();
  }

  bool _isCurrentPostIceRecoveryWatch({
    required int expectedEpoch,
    required int expectedGeneration,
  }) {
    return _getSessionEpoch() == expectedEpoch &&
        _postIceRecoveryFlowGeneration == expectedGeneration &&
        _awaitingPostIceRecoveryFlow &&
        _getPeer() != null;
  }

  void _logMediaDiagnostics(AudioTrafficStats stats) {
    final now = DateTime.now();
    final mediaPathSignature = [
      stats.selectedCandidatePairId ?? 'none',
      stats.candidateProtocol ?? 'na',
      stats.localCandidateType ?? 'na',
      stats.remoteCandidateType ?? 'na',
      stats.localCandidateAddress ?? 'na',
      stats.remoteCandidateAddress ?? 'na',
    ].join('|');
    final pathChanged = mediaPathSignature != _lastMediaPathSignature;
    final lastLogAt = _lastMediaDiagnosticsLogAt;
    if (!pathChanged &&
        lastLogAt != null &&
        now.difference(lastLogAt) < _mediaDiagnosticsLogThrottle) {
      return;
    }
    _lastMediaDiagnosticsLogAt = now;
    _lastMediaPathSignature = mediaPathSignature;
    _log('media:diag ${_buildMediaDiagnosticsMessage(stats)}');
  }

  void _reportVideoNetworkStats(AudioTrafficStats stats) {
    final handler = _onVideoNetworkStats;
    if (handler == null) {
      return;
    }
    final now = DateTime.now();
    final previousSentBytes = _lastVideoNetworkSentBytes;
    final previousAt = _lastVideoNetworkStatsAt;
    _lastVideoNetworkSentBytes = stats.sentBytes;
    _lastVideoNetworkStatsAt = now;
    if (previousSentBytes < 0 || previousAt == null) {
      return;
    }
    final sentDeltaBytes = stats.sentBytes - previousSentBytes;
    if (sentDeltaBytes <= 0) {
      unawaited(handler(stats: stats, outboundKbps: 0));
      return;
    }
    final elapsedMs = now.difference(previousAt).inMilliseconds;
    final safeElapsedMs = elapsedMs <= 0
        ? _statsPollInterval.inMilliseconds
        : elapsedMs;
    final outboundKbps = sentDeltaBytes * 8 / safeElapsedMs;
    unawaited(handler(stats: stats, outboundKbps: outboundKbps));
  }

  String _buildMediaDiagnosticsMessage(AudioTrafficStats stats) {
    return 'pair=${stats.selectedCandidatePairId ?? "none"} '
        'route=${stats.candidateProtocol ?? "na"} '
        '${stats.localCandidateType ?? "na"}:${stats.localCandidateAddress ?? "na"} '
        '-> ${stats.remoteCandidateType ?? "na"}:${stats.remoteCandidateAddress ?? "na"} '
        'rttMs=${stats.currentRoundTripTimeMs.toStringAsFixed(0)} '
        'outKbps=${stats.availableOutgoingBitrateKbps.toStringAsFixed(0)} '
        'inKbps=${stats.availableIncomingBitrateKbps.toStringAsFixed(0)} '
        'audioLoss=${stats.audioPacketsLost} '
        'videoLoss=${stats.videoPacketsLost} '
        'audioJitterMs=${stats.audioJitterMs.toStringAsFixed(0)} '
        'videoJitterMs=${stats.videoJitterMs.toStringAsFixed(0)} '
        'bytesIn=${stats.receivedBytes} bytesOut=${stats.sentBytes} '
        'audioBytesOut=${stats.audioSentBytes} '
        'videoBytes=${stats.videoBytesReceived} videoFrames=${stats.videoFramesDecoded}';
  }

  int _delta(int current, int previous) {
    if (previous < 0) {
      return 0;
    }
    return current - previous;
  }
}
