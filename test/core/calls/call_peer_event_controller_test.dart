import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_stream_controller.dart';
import 'package:peerlink/core/calls/call_peer_event_controller.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

class _DummyPeerConnection implements RTCPeerConnection {
  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Function(MediaStream stream)? onAddStream;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceGatheringState state)? onIceGatheringState;

  @override
  Function(RTCSignalingState state)? onSignalingState;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMediaStreamController extends CallMediaStreamController {
  _FakeMediaStreamController()
    : super(
        log: (_) {},
        onLocalStream: (_) {},
        onRemoteStream: (_) {},
        createRemoteRenderStream: (_) async => _FakeMediaStream('unused'),
      );

  final List<MediaStreamTrack> attachedTracks = <MediaStreamTrack>[];
  final List<MediaStream> ingestedStreams = <MediaStream>[];
  final List<MediaStreamTrack?> preferredTracks = <MediaStreamTrack?>[];

  @override
  Future<void> attachRemoteTrack(MediaStreamTrack track) async {
    attachedTracks.add(track);
  }

  @override
  Future<void> ingestRemoteStream(
    MediaStream incoming, {
    MediaStreamTrack? preferredTrack,
  }) async {
    ingestedStreams.add(incoming);
    preferredTracks.add(preferredTrack);
  }
}

class _FakeSignalingService implements SignalingService {
  final List<Map<String, dynamic>> sentIce = <Map<String, dynamic>>[];

  @override
  SignalingConnectionStatus get connectionStatus =>
      SignalingConnectionStatus.connected;

  @override
  String? get lastError => null;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      const Stream<SignalingConnectionStatus>.empty();

  @override
  Stream<String?> get lastErrorStream => const Stream<String?>.empty();

  @override
  Stream<SignalingMessage> get messages =>
      const Stream<SignalingMessage>.empty();

  @override
  Stream<List<String>> get peersStream => const Stream<List<String>>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> configureServers(List<String> endpoints) async {}

  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) async {}

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) async {
    sentIce.add(<String, dynamic>{'peerId': peerId, 'candidate': candidate});
  }

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) async {}

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {}

  @override
  Future<void> setServer(String endpoint) async {}
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(String id) : super(id, 'test');

  final List<MediaStreamTrack> _tracks = <MediaStreamTrack>[];

  @override
  bool? get active => true;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    _tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.removeWhere((existing) => existing.id == track.id);
  }

  @override
  List<MediaStreamTrack> getTracks() => List<MediaStreamTrack>.from(_tracks);

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((track) => track.kind == 'audio').toList();

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> getMediaTracks() async {}
}

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack({required this.trackId, required this.trackKind});

  final String trackId;
  final String trackKind;
  bool _enabled = true;

  @override
  String? get id => trackId;

  @override
  String? get kind => trackKind;

  @override
  String? get label => '$trackKind-$trackId';

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) {
    _enabled = b;
  }

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

CallPeerEventController _buildController({
  required _FakeSignalingService signaling,
  required _FakeMediaStreamController mediaStreamController,
  required RTCPeerConnection peer,
  required void Function(bool connected) setIceConnected,
  required void Function(bool active) setRemoteTrackSeen,
  required void Function(bool active) setRemoteAudioTrackSeen,
  required void Function(bool active) setRemoteVideoTrackSeen,
  required void Function(String value) setLastSignalingStateLabel,
  required void Function(String? trackId) onRemoteVideoTrackChanged,
  required void Function() notifyConnected,
  required void Function() ensureAudioStatsPolling,
  required void Function() armMediaFlowFallback,
  required void Function() beginIceRecoveryFlowWatch,
  required void Function() armPostIceRecoveryFlowWatch,
  required void Function() cancelIceRecoveryTimers,
  required void Function() armIceDisconnectedTimer,
  required void Function(String error) armIceFailureState,
}) {
  return CallPeerEventController(
    signaling: signaling,
    turnAllocator: null,
    mediaStreamController: mediaStreamController,
    log: (_) {},
    getPeer: () => peer,
    getPeerId: () => 'peer-b',
    getCallId: () => 'call-1',
    getMode: () => TransportMode.turn,
    getSessionEpoch: () => 1,
    getActiveTurnCredentials: () => null,
    setIceConnected: setIceConnected,
    setRemoteTrackSeen: setRemoteTrackSeen,
    setRemoteAudioTrackSeen: setRemoteAudioTrackSeen,
    setRemoteVideoTrackSeen: setRemoteVideoTrackSeen,
    setLastSignalingStateLabel: setLastSignalingStateLabel,
    onRemoteVideoTrackChanged: onRemoteVideoTrackChanged,
    notifyConnected: notifyConnected,
    ensureAudioStatsPolling: ensureAudioStatsPolling,
    armMediaFlowFallback: armMediaFlowFallback,
    beginIceRecoveryFlowWatch: beginIceRecoveryFlowWatch,
    armPostIceRecoveryFlowWatch: armPostIceRecoveryFlowWatch,
    cancelIceRecoveryTimers: cancelIceRecoveryTimers,
    armIceDisconnectedTimer: armIceDisconnectedTimer,
    armIceFailureState: armIceFailureState,
  );
}

void main() {
  group('CallPeerEventController', () {
    test('sends local ICE candidate with call context', () async {
      final peer = _DummyPeerConnection();
      final signaling = _FakeSignalingService();
      final controller = _buildController(
        signaling: signaling,
        mediaStreamController: _FakeMediaStreamController(),
        peer: peer,
        setIceConnected: (_) {},
        setRemoteTrackSeen: (_) {},
        setRemoteAudioTrackSeen: (_) {},
        setRemoteVideoTrackSeen: (_) {},
        setLastSignalingStateLabel: (_) {},
        onRemoteVideoTrackChanged: (_) {},
        notifyConnected: () {},
        ensureAudioStatsPolling: () {},
        armMediaFlowFallback: () {},
        beginIceRecoveryFlowWatch: () {},
        armPostIceRecoveryFlowWatch: () {},
        cancelIceRecoveryTimers: () {},
        armIceDisconnectedTimer: () {},
        armIceFailureState: (_) {},
      );

      controller.bind(peer);
      await peer.onIceCandidate!(
        RTCIceCandidate('candidate:1 1 udp 1 127.0.0.1 5000 typ host', '0', 0),
      );

      expect(signaling.sentIce, hasLength(1));
      expect(signaling.sentIce.single['peerId'], 'peer-b');
      expect(signaling.sentIce.single['candidate']['callId'], 'call-1');
      expect(signaling.sentIce.single['candidate']['transportMode'], 'turn');
    });

    test(
      'connected ICE state arms post-recovery watch and notifies connected',
      () {
        final peer = _DummyPeerConnection();
        final signaling = _FakeSignalingService();
        final calls = <String>[];
        final controller = _buildController(
          signaling: signaling,
          mediaStreamController: _FakeMediaStreamController(),
          peer: peer,
          setIceConnected: (value) => calls.add('ice:$value'),
          setRemoteTrackSeen: (_) {},
          setRemoteAudioTrackSeen: (_) {},
          setRemoteVideoTrackSeen: (_) {},
          setLastSignalingStateLabel: (_) {},
          onRemoteVideoTrackChanged: (_) {},
          notifyConnected: () => calls.add('notify'),
          ensureAudioStatsPolling: () {},
          armMediaFlowFallback: () {},
          beginIceRecoveryFlowWatch: () {},
          armPostIceRecoveryFlowWatch: () => calls.add('post-watch'),
          cancelIceRecoveryTimers: () {},
          armIceDisconnectedTimer: () {},
          armIceFailureState: (_) {},
        );

        controller.bind(peer);
        peer.onIceConnectionState!(
          RTCIceConnectionState.RTCIceConnectionStateConnected,
        );

        expect(
          calls,
          containsAllInOrder(<String>['ice:true', 'post-watch', 'notify']),
        );
      },
    );

    test('failed ICE state begins recovery and arms failure state', () {
      final peer = _DummyPeerConnection();
      final signaling = _FakeSignalingService();
      final calls = <String>[];
      final controller = _buildController(
        signaling: signaling,
        mediaStreamController: _FakeMediaStreamController(),
        peer: peer,
        setIceConnected: (value) => calls.add('ice:$value'),
        setRemoteTrackSeen: (_) {},
        setRemoteAudioTrackSeen: (_) {},
        setRemoteVideoTrackSeen: (_) {},
        setLastSignalingStateLabel: (_) {},
        onRemoteVideoTrackChanged: (_) {},
        notifyConnected: () {},
        ensureAudioStatsPolling: () {},
        armMediaFlowFallback: () {},
        beginIceRecoveryFlowWatch: () => calls.add('begin-watch'),
        armPostIceRecoveryFlowWatch: () {},
        cancelIceRecoveryTimers: () {},
        armIceDisconnectedTimer: () {},
        armIceFailureState: (error) => calls.add('failure:$error'),
      );

      controller.bind(peer);
      peer.onIceConnectionState!(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );

      expect(
        calls,
        containsAllInOrder(<String>[
          'ice:false',
          'begin-watch',
          'failure:ICE connection failed',
        ]),
      );
    });

    test('audio track event updates audio state and fallback hooks', () async {
      final peer = _DummyPeerConnection();
      final signaling = _FakeSignalingService();
      final mediaStreamController = _FakeMediaStreamController();
      final calls = <String>[];
      final controller = _buildController(
        signaling: signaling,
        mediaStreamController: mediaStreamController,
        peer: peer,
        setIceConnected: (_) {},
        setRemoteTrackSeen: (value) => calls.add('remote:$value'),
        setRemoteAudioTrackSeen: (value) => calls.add('audio:$value'),
        setRemoteVideoTrackSeen: (value) => calls.add('video:$value'),
        setLastSignalingStateLabel: (_) {},
        onRemoteVideoTrackChanged: (_) {},
        notifyConnected: () => calls.add('notify'),
        ensureAudioStatsPolling: () => calls.add('stats'),
        armMediaFlowFallback: () => calls.add('fallback'),
        beginIceRecoveryFlowWatch: () {},
        armPostIceRecoveryFlowWatch: () {},
        cancelIceRecoveryTimers: () {},
        armIceDisconnectedTimer: () {},
        armIceFailureState: (_) {},
      );

      controller.bind(peer);
      final audioTrack = _FakeMediaStreamTrack(
        trackId: 'audio-1',
        trackKind: 'audio',
      );
      await peer.onTrack!(
        RTCTrackEvent(track: audioTrack, streams: const <MediaStream>[]),
      );

      expect(mediaStreamController.attachedTracks, hasLength(1));
      expect(mediaStreamController.attachedTracks.single.id, 'audio-1');
      expect(
        calls,
        containsAllInOrder(<String>[
          'remote:true',
          'audio:true',
          'stats',
          'fallback',
          'notify',
        ]),
      );
    });

    test(
      'video track event prefers stream video track for rendering',
      () async {
        final peer = _DummyPeerConnection();
        final signaling = _FakeSignalingService();
        final mediaStreamController = _FakeMediaStreamController();
        String? remoteVideoTrackId;
        final controller = _buildController(
          signaling: signaling,
          mediaStreamController: mediaStreamController,
          peer: peer,
          setIceConnected: (_) {},
          setRemoteTrackSeen: (_) {},
          setRemoteAudioTrackSeen: (_) {},
          setRemoteVideoTrackSeen: (_) {},
          setLastSignalingStateLabel: (_) {},
          onRemoteVideoTrackChanged: (value) => remoteVideoTrackId = value,
          notifyConnected: () {},
          ensureAudioStatsPolling: () {},
          armMediaFlowFallback: () {},
          beginIceRecoveryFlowWatch: () {},
          armPostIceRecoveryFlowWatch: () {},
          cancelIceRecoveryTimers: () {},
          armIceDisconnectedTimer: () {},
          armIceFailureState: (_) {},
        );

        controller.bind(peer);
        final videoTrack = _FakeMediaStreamTrack(
          trackId: 'video-event',
          trackKind: 'video',
        );
        final stream = _FakeMediaStream('remote-1');
        await stream.addTrack(
          _FakeMediaStreamTrack(trackId: 'video-stream-1', trackKind: 'video'),
        );
        await stream.addTrack(
          _FakeMediaStreamTrack(trackId: 'video-stream-2', trackKind: 'video'),
        );

        await peer.onTrack!(
          RTCTrackEvent(track: videoTrack, streams: <MediaStream>[stream]),
        );

        expect(mediaStreamController.ingestedStreams, hasLength(1));
        expect(mediaStreamController.preferredTracks, hasLength(1));
        expect(
          mediaStreamController.preferredTracks.single?.id,
          'video-stream-2',
        );
        expect(remoteVideoTrackId, 'video-stream-2');
      },
    );
  });
}
