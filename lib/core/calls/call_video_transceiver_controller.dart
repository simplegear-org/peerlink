import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_video_state.dart';

class _VideoSdpSection {
  const _VideoSdpSection({required this.mid, required this.direction});

  final String mid;
  final String direction;
}

class CallVideoTransceiverController {
  const CallVideoTransceiverController({
    required CallVideoState state,
    required void Function(String message) log,
    required List<String> Function(String? sdp) extractVideoMids,
    required bool Function() getStartedAsOfferer,
    required RTCPeerConnection? Function() getPeer,
    required String Function() videoChannelSnapshot,
  }) : _state = state,
       _log = log,
       _extractVideoMids = extractVideoMids,
       _getStartedAsOfferer = getStartedAsOfferer,
       _getPeer = getPeer,
       _videoChannelSnapshot = videoChannelSnapshot;

  final CallVideoState _state;
  final void Function(String message) _log;
  final List<String> Function(String? sdp) _extractVideoMids;
  final bool Function() _getStartedAsOfferer;
  final RTCPeerConnection? Function() _getPeer;
  final String Function() _videoChannelSnapshot;

  Future<bool> ensureVideoTransceiversReady() async {
    final peer = _getPeer();
    if (peer == null) {
      _log('diagnostic:warning video:bootstrap skipped reason=peer-missing');
      return false;
    }
    await refreshVideoChannelHandles();
    if (_state.videoSendTransceiver != null &&
        _state.videoReceiveTransceiver != null) {
      return false;
    }
    try {
      _state.videoSendTransceiver ??= await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _state.videoReceiveTransceiver ??= _state.videoSendTransceiver;
      await refreshVideoChannelHandles();
      _log(
        'video:bootstrap created-on-demand '
        'shared=${identical(_state.videoSendTransceiver, _state.videoReceiveTransceiver)} '
        'sendMid=${_state.videoSendTransceiver?.mid} '
        'recvMid=${_state.videoReceiveTransceiver?.mid}',
      );
      return true;
    } catch (error) {
      _log('video:bootstrap on-demand failed error=$error');
      rethrow;
    }
  }

  Future<void> refreshVideoChannelHandles() async {
    final peer = _getPeer();
    if (peer == null) {
      _state.videoSendTransceiver = null;
      _state.videoReceiveTransceiver = null;
      _state.videoSendSender = null;
      _log('diagnostic:warning video:handles cleared reason=peer-missing');
      return;
    }
    try {
      final transceivers = List<RTCRtpTransceiver>.from(
        await peer.getTransceivers(),
      );
      final currentSendSenderId = _state.videoSendSender?.senderId;
      final expectedSendMid = _state.expectedVideoSendMid;
      final expectedReceiveMid = _state.expectedVideoReceiveMid;
      RTCRtpTransceiver? sendTransceiver;
      RTCRtpTransceiver? receiveTransceiver;
      final orderedVideoTransceivers = <RTCRtpTransceiver>[];
      var sendResolvedByExpectedMid = false;
      var receiveResolvedByExpectedMid = false;

      if (expectedSendMid != null || expectedReceiveMid != null) {
        for (final transceiver in transceivers) {
          if (expectedSendMid != null && transceiver.mid == expectedSendMid) {
            sendTransceiver ??= transceiver;
            sendResolvedByExpectedMid = true;
          }
          if (expectedReceiveMid != null &&
              transceiver.mid == expectedReceiveMid) {
            receiveTransceiver ??= transceiver;
            receiveResolvedByExpectedMid = true;
          }
        }
      }

      for (final transceiver in transceivers) {
        final mediaKind =
            transceiver.receiver.track?.kind ?? transceiver.sender.track?.kind;
        if (mediaKind != 'video' && mediaKind != null && mediaKind.isNotEmpty) {
          continue;
        }
        orderedVideoTransceivers.add(transceiver);
        final direction = await safeGetDirection(transceiver);
        final currentDirection = await safeGetCurrentDirection(transceiver);

        if (currentSendSenderId != null &&
            currentSendSenderId.isNotEmpty &&
            transceiver.sender.senderId == currentSendSenderId &&
            !sendResolvedByExpectedMid) {
          sendTransceiver = transceiver;
          continue;
        }

        if (_isSendSideDirection(direction) ||
            _isSendSideDirection(currentDirection)) {
          if (!sendResolvedByExpectedMid) {
            sendTransceiver ??= transceiver;
          }
          continue;
        }
        if (_isReceiveSideDirection(direction) ||
            _isReceiveSideDirection(currentDirection)) {
          if (!receiveResolvedByExpectedMid) {
            receiveTransceiver ??= transceiver;
          }
        }
      }

      if (orderedVideoTransceivers.length >= 2) {
        if (_getStartedAsOfferer()) {
          sendTransceiver ??= orderedVideoTransceivers[0];
          receiveTransceiver ??= orderedVideoTransceivers[1];
        } else {
          receiveTransceiver ??= orderedVideoTransceivers[0];
          sendTransceiver ??= orderedVideoTransceivers[1];
        }
      }

      if (sendTransceiver == null || receiveTransceiver == null) {
        final videoLike = transceivers.where((transceiver) {
          final senderKind = transceiver.sender.track?.kind;
          final receiverKind = transceiver.receiver.track?.kind;
          return senderKind == 'video' || receiverKind == 'video';
        }).toList();
        if (sendTransceiver == null && videoLike.isNotEmpty) {
          sendTransceiver = videoLike.first;
        }
        if (receiveTransceiver == null && videoLike.length > 1) {
          receiveTransceiver = videoLike.firstWhere(
            (candidate) => !identical(candidate, sendTransceiver),
            orElse: () => videoLike.last,
          );
        } else if (receiveTransceiver == null && sendTransceiver != null) {
          receiveTransceiver = sendTransceiver;
        }
      }

      if (identical(sendTransceiver, receiveTransceiver)) {
        receiveTransceiver = orderedVideoTransceivers.firstWhere(
          (candidate) => !identical(candidate, sendTransceiver),
          orElse: () => receiveTransceiver!,
        );
      }

      _state.videoSendTransceiver = sendTransceiver;
      _state.videoReceiveTransceiver = receiveTransceiver;
      _state.videoSendSender = sendTransceiver?.sender;
      _log(
        'video:handles refreshed '
        'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
        'videoCount=${orderedVideoTransceivers.length} '
        '${_videoChannelSnapshot()}',
      );
    } catch (error) {
      _log('video:refresh handles failed error=$error');
    }
  }

  Future<TransceiverDirection?> safeGetDirection(
    RTCRtpTransceiver transceiver,
  ) async {
    try {
      return await transceiver.getDirection();
    } catch (_) {
      return null;
    }
  }

  Future<TransceiverDirection?> safeGetCurrentDirection(
    RTCRtpTransceiver transceiver,
  ) async {
    try {
      return await transceiver.getCurrentDirection();
    } catch (_) {
      return null;
    }
  }

  void captureExpectedVideoMidsForLocalOffer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids local-offer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final localMids = _localMidsFromOffer(sdp, fallbackMids: mids);
      _state.expectedVideoSendMid = localMids.$1;
      _state.expectedVideoReceiveMid = localMids.$2;
      _log(
        'video:mids local-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteOffer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids remote-offer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final localMids = _localMidsFromRemoteOffer(sdp, fallbackMids: mids);
      _state.expectedVideoSendMid = localMids.$1;
      _state.expectedVideoReceiveMid = localMids.$2;
      _log(
        'video:mids remote-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteAnswer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids remote-answer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final currentSendMid = _state.videoSendTransceiver?.mid;
      final currentReceiveMid = _state.videoReceiveTransceiver?.mid;
      final expectedSendMid = _state.expectedVideoSendMid;
      final expectedReceiveMid = _state.expectedVideoReceiveMid;

      if (currentSendMid != null &&
          currentReceiveMid != null &&
          mids.contains(currentSendMid) &&
          mids.contains(currentReceiveMid)) {
        _state.expectedVideoSendMid = currentSendMid;
        _state.expectedVideoReceiveMid = currentReceiveMid;
      } else if (expectedSendMid != null &&
          expectedReceiveMid != null &&
          mids.contains(expectedSendMid) &&
          mids.contains(expectedReceiveMid)) {
        _state.expectedVideoSendMid = expectedSendMid;
        _state.expectedVideoReceiveMid = expectedReceiveMid;
      } else {
        _state.expectedVideoSendMid = mids[0];
        _state.expectedVideoReceiveMid = mids[1];
      }
      _log(
        'video:mids remote-answer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  Future<void> ensureVideoTransceiverDirectionsForRole() async {
    final sendTransceiver = _state.videoSendTransceiver;
    final receiveTransceiver = _state.videoReceiveTransceiver;
    if (sendTransceiver == null && receiveTransceiver == null) {
      return;
    }
    try {
      if (sendTransceiver != null &&
          receiveTransceiver != null &&
          identical(sendTransceiver, receiveTransceiver)) {
        await sendTransceiver.setDirection(TransceiverDirection.SendRecv);
        _log(
          'video:directions enforced shared=true '
          'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
          'mid=${sendTransceiver.mid}',
        );
        return;
      }
      if (sendTransceiver != null) {
        await sendTransceiver.setDirection(TransceiverDirection.SendOnly);
      }
      if (receiveTransceiver != null) {
        await receiveTransceiver.setDirection(TransceiverDirection.RecvOnly);
      }
      _log(
        'video:directions enforced '
        'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
        'sendMid=${sendTransceiver?.mid} recvMid=${receiveTransceiver?.mid}',
      );
    } catch (error) {
      _log('video:directions enforce failed error=$error');
    }
  }

  bool _isSendSideDirection(TransceiverDirection? direction) {
    return direction == TransceiverDirection.SendOnly ||
        direction == TransceiverDirection.SendRecv;
  }

  bool _isReceiveSideDirection(TransceiverDirection? direction) {
    return direction == TransceiverDirection.RecvOnly ||
        direction == TransceiverDirection.SendRecv;
  }

  (String sendMid, String receiveMid) _localMidsFromOffer(
    String? sdp, {
    required List<String> fallbackMids,
  }) {
    final sections = _extractVideoSdpSections(sdp);
    final sendMid = _firstMidWithDirection(sections, const <String>{
      'sendonly',
      'sendrecv',
    });
    final receiveMid = _firstMidWithDirection(sections, const <String>{
      'recvonly',
      'sendrecv',
    }, exceptMid: sendMid);
    return (sendMid ?? fallbackMids[0], receiveMid ?? fallbackMids[1]);
  }

  (String sendMid, String receiveMid) _localMidsFromRemoteOffer(
    String? sdp, {
    required List<String> fallbackMids,
  }) {
    final sections = _extractVideoSdpSections(sdp);
    final sendMid = _firstMidWithDirection(sections, const <String>{
      'recvonly',
      'sendrecv',
    });
    final receiveMid = _firstMidWithDirection(sections, const <String>{
      'sendonly',
      'sendrecv',
    }, exceptMid: sendMid);
    return (sendMid ?? fallbackMids[1], receiveMid ?? fallbackMids[0]);
  }

  String? _firstMidWithDirection(
    List<_VideoSdpSection> sections,
    Set<String> directions, {
    String? exceptMid,
  }) {
    for (final section in sections) {
      if (section.mid == exceptMid) {
        continue;
      }
      if (directions.contains(section.direction)) {
        return section.mid;
      }
    }
    return null;
  }

  List<_VideoSdpSection> _extractVideoSdpSections(String? sdp) {
    if (sdp == null || sdp.isEmpty) {
      return const <_VideoSdpSection>[];
    }
    final sections = <_VideoSdpSection>[];
    final lines = sdp.split('\r\n');
    var inVideoSection = false;
    String? currentMid;
    var currentDirection = 'sendrecv';

    void flushSection() {
      final mid = currentMid;
      if (!inVideoSection || mid == null || mid.isEmpty) {
        return;
      }
      sections.add(_VideoSdpSection(mid: mid, direction: currentDirection));
    }

    for (final line in lines) {
      if (line.startsWith('m=')) {
        flushSection();
        inVideoSection = line.startsWith('m=video ');
        currentMid = null;
        currentDirection = 'sendrecv';
        continue;
      }
      if (!inVideoSection) {
        continue;
      }
      if (line.startsWith('a=mid:')) {
        currentMid = line.substring('a=mid:'.length);
        continue;
      }
      if (line == 'a=sendrecv' ||
          line == 'a=sendonly' ||
          line == 'a=recvonly' ||
          line == 'a=inactive') {
        currentDirection = line.substring('a='.length);
      }
    }
    flushSection();
    return sections;
  }
}
