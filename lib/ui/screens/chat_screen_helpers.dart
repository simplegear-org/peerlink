import 'package:flutter/material.dart';

import '../state/chat_controller.dart';
import '../theme/app_theme.dart';

class ChatScreenHelpers {
  const ChatScreenHelpers._();

  static String statusLabel(
    ChatConnectionStatus status,
    String? connectError,
    {
    bool isPeerOnline = false,
    DateTime? lastSeenAt,
    DateTime? fallbackLastSeenAt,
  }
  ) {
    switch (status) {
      case ChatConnectionStatus.connecting:
        return 'Подключение...';
      case ChatConnectionStatus.error:
        return connectError == null || connectError.isEmpty
            ? 'Ошибка подключения'
            : connectError;
      case ChatConnectionStatus.connected:
      case ChatConnectionStatus.disconnected:
        return lastSeenLabel(
          isPeerOnline: isPeerOnline,
          lastSeenAt: lastSeenAt,
          fallbackLastSeenAt: fallbackLastSeenAt,
        );
    }
  }

  static String lastSeenLabel({
    required bool isPeerOnline,
    DateTime? lastSeenAt,
    DateTime? fallbackLastSeenAt,
    String offlineFallback = 'Не в сети',
  }) {
    if (isPeerOnline) {
      return 'На связи';
    }
    final effectiveLastSeen = lastSeenAt ?? fallbackLastSeenAt;
    if (effectiveLastSeen != null) {
      return _formatLastSeen(effectiveLastSeen);
    }
    return offlineFallback;
  }

  static Color statusColor(ChatConnectionStatus status) {
    switch (status) {
      case ChatConnectionStatus.connected:
        return AppTheme.pine;
      case ChatConnectionStatus.connecting:
      case ChatConnectionStatus.error:
        return AppTheme.accent;
      case ChatConnectionStatus.disconnected:
        return AppTheme.muted;
    }
  }

  static String formatComposerDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _formatLastSeen(DateTime seenAt) {
    final now = DateTime.now();
    final diff = now.difference(seenAt);
    if (diff.inMinutes < 1) {
      return 'Был(а) в сети только что';
    }
    if (diff.inHours < 1) {
      return 'Был(а) в сети ${diff.inMinutes} мин назад';
    }
    if (diff.inHours < 24) {
      return 'Был(а) в сети ${diff.inHours} ч назад';
    }
    final day = seenAt.day.toString().padLeft(2, '0');
    final month = seenAt.month.toString().padLeft(2, '0');
    final hour = seenAt.hour.toString().padLeft(2, '0');
    final minute = seenAt.minute.toString().padLeft(2, '0');
    return 'Был(а) в сети $day.$month в $hour:$minute';
  }
}
