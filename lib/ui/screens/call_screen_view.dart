import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/calls/call_models.dart';
import '../../core/node/node_facade.dart';
import '../theme/app_theme.dart';
import 'package:peerlink/ui/screens/call_screen_video_view.dart';
import 'package:peerlink/ui/screens/call_screen_widgets.dart';
import 'call_screen_styles.dart';

class CallScreenContent extends StatelessWidget {
  final NodeFacade facade;
  final CallState state;
  final String contactName;
  final ValueListenable<int>? dataBytesListenable;
  final int currentDataBytes;
  final double ringingPulse;
  final double mediaTopInset;
  final double mediaBottomInset;

  const CallScreenContent({
    super.key,
    required this.facade,
    required this.state,
    required this.contactName,
    required this.dataBytesListenable,
    required this.currentDataBytes,
    required this.ringingPulse,
    required this.mediaTopInset,
    required this.mediaBottomInset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.ink.withValues(alpha: 0.96),
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(child: _buildMiddleZone(context)),
                Padding(
                  padding: CallScreenStyles.bottomControlsPadding.copyWith(
                    bottom: mediaBottomInset + 8,
                  ),
                  child: SizedBox(
                    height: CallScreenStyles.bottomControlsHeight,
                    child: _buildBottomZone(context),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: mediaTopInset,
            left: CallScreenStyles.overlayHorizontalPadding.left,
            right: CallScreenStyles.overlayHorizontalPadding.right,
            child: _buildTopZone(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopZone(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final nameFont = math.max(18.0, constraints.maxWidth * 0.07);
        final metaFont = math.max(9.0, constraints.maxWidth * 0.028);

        return SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatPill(
                    label: 'Статус',
                    value: _statusLabel(),
                    fontSize: metaFont,
                    valueColor: _statusColor(),
                  ),
                  if (dataBytesListenable != null)
                    ValueListenableBuilder<int>(
                      valueListenable: dataBytesListenable!,
                      builder: (context, bytes, child) {
                        return StatPill(
                          label: 'Канал',
                          value:
                              '${_transportBadge(state)} ${_formatBytes(bytes)}${_videoCodecSuffix(state)}',
                          fontSize: metaFont,
                        );
                      },
                    )
                  else
                    StatPill(
                      label: 'Канал',
                      value:
                          '${_transportBadge(state)} ${_formatBytes(currentDataBytes)}${_videoCodecSuffix(state)}',
                      fontSize: metaFont,
                    ),
                ],
              ),
              const SizedBox(height: CallScreenStyles.topStatSpacing),
              Text(
                contactName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: nameFont,
                  height: 0.96,
                  shadows: const [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 16,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiddleZone(BuildContext context) {
    if (_showsCallProgressVisualization) {
      return _buildCallProgressVisualization(context);
    }

    if (!_showsVideoStage) {
      return Center(
        child: Container(
          width: CallScreenStyles.middleIconSize,
          height: CallScreenStyles.middleIconSize,
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(CallScreenStyles.middleIconRadius),
          ),
          child: const Icon(
            Icons.call_rounded,
            size: CallScreenStyles.middleIconGlyphSize,
            color: AppTheme.ink,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = constraints.maxWidth * 0.22;
        final previewHeight = constraints.maxHeight * 0.30;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: VideoStreamView(
                  stream: _remoteDisplayStream,
                  trackId: state.remoteVideoTrackId,
                  active: _showsRemoteVideoStage,
                  mirrored: false,
                  placeholder: _buildVideoPlaceholder(context),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 160,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xA6000000),
                        Color(0x5C000000),
                        Color(0x00000000),
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: CallScreenStyles.previewRightOffset,
              bottom: CallScreenStyles.previewBottomOffset,
              child: SizedBox(
                width: previewWidth.clamp(68, 110),
                height: previewHeight.clamp(96, 150),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CallScreenStyles.previewRadius),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      borderRadius: BorderRadius.circular(CallScreenStyles.previewRadius),
                    ),
                    child: VideoStreamView(
                      stream: _localPreviewStream,
                      active: _hasLocalVideo,
                      mirrored: state.isFrontCamera,
                      placeholder: const Center(
                        child: Icon(Icons.videocam_rounded, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomZone(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (state.isIncoming) {
          return Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.pine,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    minimumSize: Size(0, constraints.maxHeight),
                  ),
                  onPressed: () => unawaited(facade.acceptIncomingCall()),
                  icon: Icon(
                    state.mediaType == CallMediaType.video
                        ? Icons.videocam_rounded
                        : Icons.call,
                  ),
                  label: const Text('Ответить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    minimumSize: Size(0, constraints.maxHeight),
                  ),
                  onPressed: () => unawaited(facade.rejectIncomingCall()),
                  icon: const Icon(Icons.call_end),
                  label: const Text('Отклонить'),
                ),
              ),
            ],
          );
        }

        final size = (constraints.maxHeight * 0.74).clamp(42.0, 56.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ActionCircleButton(
              size: size,
              icon: state.isMuted ? Icons.mic_off : Icons.mic,
              onPressed: () => unawaited(facade.toggleCallMuted()),
            ),
            ActionCircleButton(
              size: size,
              icon: state.speakerOn ? Icons.volume_up : Icons.hearing,
              onPressed: () =>
                  unawaited(facade.setCallSpeakerOn(!state.speakerOn)),
            ),
            ActionCircleButton(
              size: size,
              icon: state.localVideoEnabled
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              foregroundColor: (!_canToggleVideo || state.videoToggleInProgress)
                  ? Colors.white54
                  : Colors.white,
              onPressed: () {
                if (_canToggleVideo && !state.videoToggleInProgress) {
                  unawaited(facade.toggleCallVideo());
                }
              },
              backgroundColor:
                  _canToggleVideo ? null : Colors.white.withValues(alpha: 0.05),
            ),
            ActionCircleButton(
              size: size,
              icon: Icons.flip_camera_ios_rounded,
              onPressed: _hasLocalVideo
                  ? () => unawaited(facade.flipCallCamera())
                  : () {},
              backgroundColor:
                  _hasLocalVideo ? null : Colors.white.withValues(alpha: 0.05),
              foregroundColor: _hasLocalVideo ? Colors.white : Colors.white38,
            ),
            ActionCircleButton(
              size: size,
              icon: Icons.call_end,
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              onPressed: () => unawaited(facade.endCall()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallProgressVisualization(BuildContext context) {
    final theme = Theme.of(context);
    final pulse = Curves.easeInOut.transform(ringingPulse);
    final outerSize = 142.0 + (pulse * 34.0);
    final middleSize = 108.0 + (pulse * 20.0);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: outerSize,
                  height: outerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7AE582).withValues(
                      alpha: 0.05 + (0.08 * (1 - pulse)),
                    ),
                  ),
                ),
                Container(
                  width: middleSize,
                  height: middleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07 + (0.05 * (1 - pulse))),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                ),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentSoft.withValues(alpha: 0.20),
                        blurRadius: 28,
                        spreadRadius: 2 + (pulse * 4),
                      ),
                    ],
                  ),
                  child: Icon(_progressIcon(), size: 40, color: AppTheme.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _progressTitle(),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _progressSubtitle(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, size: 48, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              contactName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasLocalVideo =>
      state.localVideoEnabled && (state.localStream?.getVideoTracks().isNotEmpty ?? false);
  bool get _canToggleVideo => state.isActive;
  bool get _showsCallProgressVisualization =>
      state.phase == CallPhase.outgoingRinging ||
      state.phase == CallPhase.incomingRinging ||
      state.phase == CallPhase.connecting;
  bool get _showsRemoteVideoStage => state.remoteVideoEnabled || state.remoteVideoActive;
  bool get _hasRemoteVideo => _showsRemoteVideoStage && state.remoteStream != null;
  bool get _showsVideoStage => _hasLocalVideo || _showsRemoteVideoStage;
  MediaStream? get _localPreviewStream => _hasLocalVideo ? state.localStream : null;
  MediaStream? get _remoteDisplayStream => _hasRemoteVideo ? state.remoteStream : null;

  IconData _progressIcon() {
    switch (state.phase) {
      case CallPhase.outgoingRinging:
        return Icons.wifi_calling_3_rounded;
      case CallPhase.incomingRinging:
        return Icons.call_rounded;
      case CallPhase.connecting:
        return Icons.sync_rounded;
      case CallPhase.active:
      case CallPhase.ended:
      case CallPhase.failed:
      case CallPhase.idle:
        return Icons.call_rounded;
    }
  }

  String _progressTitle() {
    switch (state.phase) {
      case CallPhase.outgoingRinging:
        return 'Дозваниваемся';
      case CallPhase.incomingRinging:
        return 'Входящий звонок';
      case CallPhase.connecting:
        return 'Устанавливаем соединение';
      case CallPhase.active:
      case CallPhase.ended:
      case CallPhase.failed:
      case CallPhase.idle:
        return contactName;
    }
  }

  String _progressSubtitle() {
    switch (state.phase) {
      case CallPhase.outgoingRinging:
        return 'Ждем, пока собеседник ответит';
      case CallPhase.incomingRinging:
        return 'Собеседник пытается связаться с вами';
      case CallPhase.connecting:
        return 'Поднимаем транспорт, аудио и видеоканал';
      case CallPhase.active:
      case CallPhase.ended:
      case CallPhase.failed:
      case CallPhase.idle:
        return '';
    }
  }

  String _statusLabel() {
    switch (state.phase) {
      case CallPhase.incomingRinging:
        return 'Входящий';
      case CallPhase.outgoingRinging:
        return 'Дозвон';
      case CallPhase.connecting:
        return 'Подключение';
      case CallPhase.active:
        final duration = _formatDuration();
        return duration == '00:00' ? 'Соединено' : duration;
      case CallPhase.ended:
        return 'Завершён';
      case CallPhase.failed:
        return 'Ошибка';
      case CallPhase.idle:
        return 'Ожидание';
    }
  }

  Color _statusColor() {
    switch (state.phase) {
      case CallPhase.incomingRinging:
      case CallPhase.outgoingRinging:
      case CallPhase.connecting:
        return const Color(0xFFFFD166);
      case CallPhase.active:
        return const Color(0xFF7AE582);
      case CallPhase.ended:
      case CallPhase.idle:
        return Colors.white;
      case CallPhase.failed:
        return const Color(0xFFFF6B6B);
    }
  }

  String _formatDuration() {
    final connectedAt = state.connectedAt;
    if (connectedAt == null) {
      return '00:00';
    }
    final elapsed = DateTime.now().difference(connectedAt);
    final totalSeconds = elapsed.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _transportBadge(CallState state) {
    final label = (state.transportLabel ?? '').toLowerCase();
    if (label.contains('turn') || label.contains('relay')) {
      return 'T';
    }
    if (label.contains('direct')) {
      return 'D';
    }
    final mode = state.transportMode?.name.toLowerCase() ?? '';
    if (mode == 'turn') {
      return 'T';
    }
    if (mode == 'direct') {
      return 'D';
    }
    return '?';
  }

  String _videoCodecSuffix(CallState state) {
    final hasVideoMode =
        state.localVideoEnabled || state.remoteVideoEnabled || state.remoteVideoActive;
    final codec = state.videoCodec;
    if (!hasVideoMode || codec == null || codec.isEmpty) {
      return '';
    }
    return ' $codec';
  }
}
