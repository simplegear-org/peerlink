import 'call_control_signal_helper.dart';
import 'call_models.dart';
import 'call_runtime_tracking.dart';

class CallAudioMuteSender {
  const CallAudioMuteSender({
    required CallControlSignalHelper controlSignalHelper,
    required CallRuntimeTracking runtimeTracking,
    required CallState Function() getState,
    required void Function(String message) log,
  }) : _controlSignalHelper = controlSignalHelper,
       _runtimeTracking = runtimeTracking,
       _getState = getState,
       _log = log;

  final CallControlSignalHelper _controlSignalHelper;
  final CallRuntimeTracking _runtimeTracking;
  final CallState Function() _getState;
  final void Function(String message) _log;

  void send(bool muted, {required String purpose}) {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    final peerId = state.peerId;
    final callId = state.callId;
    if (peerId == null || callId == null) {
      return;
    }
    final version = _runtimeTracking.nextLocalAudioMuteVersion();
    _log(
      'audioMute:send peerId=$peerId callId=$callId '
      'muted=$muted version=$version purpose="$purpose"',
    );
    _controlSignalHelper.sendDetached(peerId, 'call_audio_mute_state', {
      'callId': callId,
      'signalScope': 'call',
      'muted': muted,
      'version': version,
    }, purpose: purpose);
  }
}
