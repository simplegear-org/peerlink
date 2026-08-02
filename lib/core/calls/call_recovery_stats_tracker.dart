import 'call_media_stats_utils.dart';

class CallRecoveryStatsTracker {
  int? _lastReceivedBytes;

  void reset() {
    _lastReceivedBytes = null;
  }

  bool recordInboundAdvanced(AudioTrafficStats stats) {
    if (stats.selectedCandidatePairId == null) {
      return false;
    }
    final receivedBytes = stats.receivedBytes;
    final previous = _lastReceivedBytes;
    _lastReceivedBytes = receivedBytes;
    if (receivedBytes <= 0) {
      return false;
    }
    if (previous != null && receivedBytes <= previous) {
      return false;
    }
    return true;
  }
}
