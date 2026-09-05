import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/ui/screens/call_screen_video_view.dart';

void main() {
  group('shouldRefreshVideoRenderer', () {
    test('returns true when remote track id changes on same stream', () {
      expect(
        shouldRefreshVideoRenderer(
          oldSignature: 'stream-1|video-a|1|video-a',
          newSignature: 'stream-1|video-a|1|video-b',
          oldTrackId: 'video-a',
          newTrackId: 'video-b',
          oldStreamId: 'stream-1',
          newStreamId: 'stream-1',
          oldActive: true,
          newActive: true,
        ),
        isTrue,
      );
    });

    test('returns true when stream becomes inactive', () {
      expect(
        shouldRefreshVideoRenderer(
          oldSignature: 'stream-1|video-a|1|video-a',
          newSignature: 'stream-1|video-a|1|video-a',
          oldTrackId: 'video-a',
          newTrackId: 'video-a',
          oldStreamId: 'stream-1',
          newStreamId: 'stream-1',
          oldActive: true,
          newActive: false,
        ),
        isTrue,
      );
    });

    test('returns false when renderer source is unchanged', () {
      expect(
        shouldRefreshVideoRenderer(
          oldSignature: 'stream-1|video-a|1|video-a',
          newSignature: 'stream-1|video-a|1|video-a',
          oldTrackId: 'video-a',
          newTrackId: 'video-a',
          oldStreamId: 'stream-1',
          newStreamId: 'stream-1',
          oldActive: true,
          newActive: true,
        ),
        isFalse,
      );
    });
  });

  group('resolveRendererTrackId', () {
    test('keeps explicit track id only when it exists in stream', () {
      expect(
        resolveRendererTrackId(
          availableTrackIds: const ['video-a', 'video-b'],
          requestedTrackId: 'video-b',
        ),
        'video-b',
      );
    });

    test('drops stale explicit track id and falls back to whole stream', () {
      expect(
        resolveRendererTrackId(
          availableTrackIds: const ['video-a', 'video-b'],
          requestedTrackId: 'video-stale',
        ),
        'video-b',
      );
    });

    test('returns null when stream has no video tracks', () {
      expect(
        resolveRendererTrackId(
          availableTrackIds: const <String>[],
          requestedTrackId: 'video-a',
        ),
        isNull,
      );
    });
  });

  group('hasRenderableVideo', () {
    test('returns true when requested track exists', () {
      expect(
        hasRenderableVideo(
          availableTrackIds: const ['video-a', 'video-b'],
          requestedTrackId: 'video-a',
        ),
        isTrue,
      );
    });

    test(
      'returns true when requested track is stale but stream has fallback',
      () {
        expect(
          hasRenderableVideo(
            availableTrackIds: const ['video-a', 'video-b'],
            requestedTrackId: 'video-stale',
          ),
          isTrue,
        );
      },
    );

    test(
      'returns false when requested track is stale and stream has no video',
      () {
        expect(
          hasRenderableVideo(
            availableTrackIds: const <String>[],
            requestedTrackId: 'video-stale',
          ),
          isFalse,
        );
      },
    );
  });
}
