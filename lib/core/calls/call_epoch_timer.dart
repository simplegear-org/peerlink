import 'dart:async';

class CallEpochTimer {
  const CallEpochTimer._();

  static Timer arm({
    required Duration duration,
    required int expectedEpoch,
    required int Function() getCurrentEpoch,
    required FutureOr<void> Function() onCurrent,
    FutureOr<void> Function()? onStale,
  }) {
    return Timer(duration, () {
      if (getCurrentEpoch() != expectedEpoch) {
        final stale = onStale;
        if (stale != null) {
          unawaited(Future<void>.sync(stale));
        }
        return;
      }
      unawaited(Future<void>.sync(onCurrent));
    });
  }
}
