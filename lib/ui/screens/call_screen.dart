import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/calls/call_models.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/app_file_logger.dart';
import 'package:peerlink/ui/screens/call_screen_view.dart';

class CallScreen extends StatefulWidget {
  final NodeFacade facade;
  final CallState state;
  final String contactName;
  final ValueListenable<int>? dataBytesListenable;

  const CallScreen({
    super.key,
    required this.facade,
    required this.state,
    required this.contactName,
    this.dataBytesListenable,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;
  Timer? _ringingPulseTimer;
  double _ringingPulse = 0.0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
    _syncRingingPulse();
  }

  @override
  void didUpdateWidget(covariant CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.connectedAt != widget.state.connectedAt ||
        oldWidget.state.phase != widget.state.phase) {
      _syncTicker();
      _syncRingingPulse();
    }
    if (oldWidget.state.remoteVideoEnabled != widget.state.remoteVideoEnabled ||
        oldWidget.state.remoteVideoActive != widget.state.remoteVideoActive ||
        oldWidget.state.remoteVideoTrackId != widget.state.remoteVideoTrackId ||
        oldWidget.state.remoteStream?.id != widget.state.remoteStream?.id) {
      AppFileLogger.log(
        '[call_screen] remote stage enabled=${widget.state.remoteVideoEnabled} '
        'active=${widget.state.remoteVideoActive} '
        'trackId=${widget.state.remoteVideoTrackId} '
        'streamId=${widget.state.remoteStream?.id} '
        'streamVideo=${widget.state.remoteStream?.getVideoTracks().length ?? 0}',
        name: 'App',
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ringingPulseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    return CallScreenContent(
      facade: widget.facade,
      state: widget.state,
      contactName: widget.contactName,
      dataBytesListenable: widget.dataBytesListenable,
      currentDataBytes: _currentDataBytes,
      ringingPulse: _ringingPulse,
      mediaTopInset: math.max(6, mediaPadding.top + 2),
      mediaBottomInset: math.max(12, mediaPadding.bottom + 8),
    );
  }

  void _syncTicker() {
    _ticker?.cancel();
    final connectedAt = widget.state.connectedAt;
    if (widget.state.phase != CallPhase.active || connectedAt == null) {
      return;
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _syncRingingPulse() {
    _ringingPulseTimer?.cancel();
    final phase = widget.state.phase;
    final showsProgress = phase == CallPhase.outgoingRinging ||
        phase == CallPhase.incomingRinging ||
        phase == CallPhase.connecting;
    if (!showsProgress) {
      _ringingPulse = 0.0;
      return;
    }
    _ringingPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ringingPulse = _ringingPulse == 0.0 ? 1.0 : 0.0;
      });
    });
  }

  int get _currentDataBytes =>
      widget.dataBytesListenable?.value ??
      (widget.state.bytesSent + widget.state.bytesReceived);
}
