import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_stream_controller.dart';

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack({required this.trackId, required this.trackKind});

  final String trackId;
  final String trackKind;
  bool trackEnabled = true;
  var stopCalls = 0;

  @override
  String? get id => trackId;

  @override
  String? get kind => trackKind;

  @override
  String? get label => '$trackKind-$trackId';

  @override
  bool get enabled => trackEnabled;

  @override
  set enabled(bool b) {
    trackEnabled = b;
  }

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(String id) : super(id, 'test');

  final List<MediaStreamTrack> _tracks = <MediaStreamTrack>[];
  final List<String> operations = <String>[];
  var disposeCalls = 0;

  @override
  bool? get active => true;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    _tracks.add(track);
    operations.add('add:${track.kind}:${track.id}');
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.removeWhere((existing) => existing.id == track.id);
    operations.add('remove:${track.kind}:${track.id}');
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

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  group('CallMediaStreamController', () {
    test(
      'attachRemoteTrack suppresses duplicate reattach for same track',
      () async {
        final published = <MediaStream>[];
        final syntheticStream = _FakeMediaStream('remote-stream');
        final controller = CallMediaStreamController(
          log: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: published.add,
          createRemoteRenderStream: (_) async => syntheticStream,
        );
        final audioTrack = _FakeMediaStreamTrack(
          trackId: 'audio-1',
          trackKind: 'audio',
        );

        await controller.attachRemoteTrack(audioTrack);
        await controller.attachRemoteTrack(audioTrack);

        expect(published, hasLength(1));
        expect(syntheticStream.getAudioTracks().map((track) => track.id), [
          'audio-1',
        ]);
        expect(
          syntheticStream.operations,
          equals(<String>['add:audio:audio-1']),
        );
      },
    );

    test('attachRemoteTrack replaces previous same-kind track', () async {
      final published = <MediaStream>[];
      final syntheticStream = _FakeMediaStream('remote-stream');
      final controller = CallMediaStreamController(
        log: (_) {},
        onLocalStream: (_) {},
        onRemoteStream: published.add,
        createRemoteRenderStream: (_) async => syntheticStream,
      );

      await controller.attachRemoteTrack(
        _FakeMediaStreamTrack(trackId: 'video-1', trackKind: 'video'),
      );
      await controller.attachRemoteTrack(
        _FakeMediaStreamTrack(trackId: 'video-2', trackKind: 'video'),
      );

      expect(published, hasLength(2));
      expect(syntheticStream.getVideoTracks().map((track) => track.id), [
        'video-2',
      ]);
      expect(
        syntheticStream.operations,
        equals(<String>[
          'add:video:video-1',
          'remove:video:video-1',
          'add:video:video-2',
        ]),
      );
    });

    test(
      'ingestRemoteStream publishes native stream when it contains video',
      () async {
        final published = <MediaStream>[];
        final syntheticStream = _FakeMediaStream('remote-stream');
        final incomingStream = _FakeMediaStream('incoming-stream');
        final preferredVideoTrack = _FakeMediaStreamTrack(
          trackId: 'video-preferred',
          trackKind: 'video',
        );
        final trailingVideoTrack = _FakeMediaStreamTrack(
          trackId: 'video-trailing',
          trackKind: 'video',
        );
        await incomingStream.addTrack(preferredVideoTrack);
        await incomingStream.addTrack(trailingVideoTrack);
        final controller = CallMediaStreamController(
          log: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: published.add,
          createRemoteRenderStream: (_) async => syntheticStream,
        );

        await controller.ingestRemoteStream(
          incomingStream,
          preferredTrack: preferredVideoTrack,
        );

        expect(published, hasLength(1));
        expect(published.single, same(incomingStream));
        expect(incomingStream.getVideoTracks().map((track) => track.id), [
          'video-preferred',
          'video-trailing',
        ]);
        expect(syntheticStream.operations, isEmpty);
      },
    );

    test(
      'ingestRemoteStream does not dispose native remote stream on cleanup',
      () async {
        final published = <MediaStream>[];
        final incomingStream = _FakeMediaStream('incoming-stream');
        await incomingStream.addTrack(
          _FakeMediaStreamTrack(trackId: 'video-1', trackKind: 'video'),
        );
        final controller = CallMediaStreamController(
          log: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: published.add,
          createRemoteRenderStream: (_) async =>
              _FakeMediaStream('remote-stream'),
        );

        await controller.ingestRemoteStream(incomingStream);
        await controller.disposeRemoteStream();

        expect(published.single, same(incomingStream));
        expect(incomingStream.disposeCalls, 0);
      },
    );

    test(
      'clearRemoteRenderStreamTracks clears synthetic stream and republishes it',
      () async {
        final published = <MediaStream>[];
        final syntheticStream = _FakeMediaStream('remote-stream');
        final controller = CallMediaStreamController(
          log: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: published.add,
          createRemoteRenderStream: (_) async => syntheticStream,
        );

        await controller.attachRemoteTrack(
          _FakeMediaStreamTrack(trackId: 'audio-1', trackKind: 'audio'),
        );
        await controller.attachRemoteTrack(
          _FakeMediaStreamTrack(trackId: 'video-1', trackKind: 'video'),
        );

        await controller.clearRemoteRenderStreamTracks();

        expect(published, hasLength(3));
        expect(published.last, same(syntheticStream));
        expect(syntheticStream.getTracks(), isEmpty);
        expect(
          syntheticStream.operations,
          equals(<String>[
            'add:audio:audio-1',
            'add:video:video-1',
            'remove:audio:audio-1',
            'remove:video:video-1',
          ]),
        );
      },
    );
  });
}
