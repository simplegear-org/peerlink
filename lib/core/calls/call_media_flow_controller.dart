import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import 'call_epoch_timer.dart';
import 'call_live_media_stall_detector.dart';
import 'call_media_diagnostics_formatter.dart';
import 'call_media_flow_stats_tracker.dart';
import 'call_media_stats_utils.dart';
import 'call_post_ice_recovery_flow_watch.dart';

typedef CallVideoNetworkStatsHandler =
    Future<void> Function({
      required AudioTrafficStats stats,
      required double outboundKbps,
    });

typedef CallRecoveryStatsHandler = void Function(AudioTrafficStats stats);

class CallMediaFlowController {
  static const String iceReconnectStalledReason =
      CallPostIceRecoveryFlowWatch.iceReconnectStalledReason;

  static const Duration _statsPollInterval = Duration(seconds: 1);
  static const Duration _videoWaitLogThrottle = Duration(seconds: 4);
  static const Duration _mediaDiagnosticsLogThrottle = Duration(seconds: 5);

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
  late final CallMediaFlowStatsTracker _flowStatsTracker;
  late final CallPostIceRecoveryFlowWatch _postIceRecoveryFlowWatch;
  late final CallLiveMediaStallDetector _liveMediaStallDetector;

  Timer? _audioStatsTimer;
  Timer? _mediaFlowFallbackTimer;
  DateTime? _lastVideoWaitingLogAt;
  DateTime? _lastMediaDiagnosticsLogAt;
  String? _lastMediaPathSignature;

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
       _onVideoNetworkStats = onVideoNetworkStats {
    _flowStatsTracker = CallMediaFlowStatsTracker();
    _postIceRecoveryFlowWatch = CallPostIceRecoveryFlowWatch(
      log: _log,
      getPeer: _getPeer,
      getIceConnected: _getIceConnected,
      getIceRecoveryInProgress: _getIceRecoveryInProgress,
      getRemoteAudioMuted: _getRemoteAudioMuted,
      getRemoteAudioFlowSeen: _getRemoteAudioFlowSeen,
      getRemoteVideoEnabled: _getRemoteVideoEnabled,
      getRemoteVideoTrackSeen: _getRemoteVideoTrackSeen,
      getRemoteVideoFlowSeen: _getRemoteVideoFlowSeen,
      setRemoteAudioFlowSeen: _setRemoteAudioFlowSeen,
      setRemoteVideoFlowSeen: _setRemoteVideoFlowSeen,
      onRemoteVideoFlowChanged: _onRemoteVideoFlowChanged,
      onIceMediaRecoveryCompleted: _onIceMediaRecoveryCompleted,
      onIceReconnectStalled: _onIceReconnectStalled,
      onPostIceRecoveryFlowStalled: _onPostIceRecoveryFlowStalled,
      onPostIceRecoveryVideoOnlyStalled: _onPostIceRecoveryVideoOnlyStalled,
      getSessionEpoch: _getSessionEpoch,
    );
    _liveMediaStallDetector = CallLiveMediaStallDetector(
      log: _log,
      getMediaFlowNotified: _getMediaFlowNotified,
      getIceConnected: _getIceConnected,
      getIceRecoveryInProgress: _getIceRecoveryInProgress,
      getPeer: _getPeer,
      getRemoteAudioTrackSeen: _getRemoteAudioTrackSeen,
      getRemoteAudioMuted: _getRemoteAudioMuted,
      getLocalAudioMuted: _getLocalAudioMuted,
      getRemoteVideoEnabled: _getRemoteVideoEnabled,
      getRemoteVideoTrackSeen: _getRemoteVideoTrackSeen,
      getRemoteVideoFlowSeen: _getRemoteVideoFlowSeen,
      onLiveMediaFlowStalled: _onLiveMediaFlowStalled,
      onLocalAudioOutboundStalled: _onLocalAudioOutboundStalled,
    );
  }

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
    _flowStatsTracker.reset();
    _lastVideoWaitingLogAt = null;
    _lastMediaDiagnosticsLogAt = null;
    _lastMediaPathSignature = null;
    _liveMediaStallDetector.reset();
    _postIceRecoveryFlowWatch.clear();
  }

  void beginIceRecoveryFlowWatch() {
    _postIceRecoveryFlowWatch.begin(
      resetMediaFlowBaselines: _flowStatsTracker.resetFlowBaselines,
      resetLiveMediaBaselines: () {
        _liveMediaStallDetector.resetBaseline();
        _liveMediaStallDetector.resetVideoStallPolls();
      },
    );
  }

  void resetPostIceRecoveryFlowWatch({required String reason}) {
    _postIceRecoveryFlowWatch.reset(reason: reason);
  }

  void armPostIceRecoveryFlowWatch() {
    _postIceRecoveryFlowWatch.arm();
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
    _mediaFlowFallbackTimer = CallEpochTimer.arm(
      duration: const Duration(milliseconds: 1400),
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getSessionEpoch,
      onStale: () {
        _mediaFlowFallbackTimer = null;
      },
      onCurrent: () {
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
      },
    );
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
      _flowStatsTracker.reportVideoNetworkStats(
        stats: stats,
        fallbackInterval: _statsPollInterval,
        handler: _onVideoNetworkStats,
      );
      final statsDelta = _flowStatsTracker.reportableStatsDelta(stats);
      if (statsDelta != null) {
        _onStats(
          sentBytes: statsDelta.sentBytes,
          receivedBytes: statsDelta.receivedBytes,
        );
      }
      if (!_getRemoteAudioFlowSeen() &&
          _flowStatsTracker.detectInboundAudioFlow(stats)) {
        _setRemoteAudioFlowSeen(true);
        cancelMediaFlowFallback();
        _log('audio:flow detected');
        _postIceRecoveryFlowWatch.completeIfReady();
        if (!_getMediaFlowNotified()) {
          _setMediaFlowNotified(true);
          unawaited(_onMediaFlow());
        }
        _notifyConnected();
      }
      if (_getRemoteVideoEnabled() &&
          !_getRemoteVideoFlowSeen() &&
          _flowStatsTracker.detectInboundVideoFlow(stats)) {
        _setRemoteVideoFlowSeen(true);
        _markRemoteVideoFlowDetected();
        _log(
          'video:flow detected remoteTrackSeen=${_getRemoteVideoTrackSeen()}',
        );
        _onRemoteVideoFlowChanged(true);
        _postIceRecoveryFlowWatch.completeIfReady();
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
            'lastVideoBytes=${_flowStatsTracker.lastInboundVideoBytes} '
            'videoFrames=${stats.videoFramesDecoded} '
            'lastVideoFrames=${_flowStatsTracker.lastInboundVideoFramesDecoded}',
          );
        }
      }
      _liveMediaStallDetector.evaluate(stats);
    } catch (error) {
      _log('audio:stats poll error=$error');
    }
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
    _log('media:diag ${CallMediaDiagnosticsFormatter.format(stats)}');
  }
}
