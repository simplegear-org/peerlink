import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'call_log_context.dart';
import 'call_models.dart';
import '../transport/transport_mode.dart';

typedef CallRuntimeContextProvider =
    ({
      String? peerId,
      String? callId,
      int epoch,
      String role,
      CallMediaType mediaType,
      TransportMode? transportMode,
      CallPhase? phase,
      String signalingState,
    })
    Function();

class CallRuntimeLogger {
  CallRuntimeLogger({
    required String channel,
    required String Function() getOwnerId,
    required CallRuntimeContextProvider getContext,
  }) : _channel = channel,
       _getOwnerId = getOwnerId,
       _getContext = getContext;

  final String _channel;
  final String Function() _getOwnerId;
  final CallRuntimeContextProvider _getContext;
  int _seq = 0;

  void log(String message, {Object? error, StackTrace? stackTrace}) {
    final context = _getContext();
    final structuredContext = buildStructuredCallLogContext(
      scope: _channel,
      peerId: context.peerId,
      callId: context.callId,
      epoch: context.epoch,
      role: context.role,
      mediaType: context.mediaType,
      transportMode: context.transportMode,
      phase: context.phase,
      signalingState: context.signalingState,
    );
    AppFileLogger.log(
      '[$_channel][${_getOwnerId()}][${_seq++}]$structuredContext $message',
      name: 'call',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
