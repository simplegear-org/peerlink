import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageEmojiPresentation {
  final int emojiCount;

  const MessageEmojiPresentation._(this.emojiCount);

  static MessageEmojiPresentation? tryParse(Message message) {
    if (message.kind != MessageKind.text) {
      return null;
    }
    final raw = message.text.trim();
    if (raw.isEmpty || raw.length > 32) {
      return null;
    }

    final scalars = raw.runes.toList(growable: false);
    var emojiCount = 0;
    var index = 0;

    while (index < scalars.length) {
      final scalar = scalars[index];
      if (_isWhitespace(scalar)) {
        index++;
        continue;
      }
      final nextIndex = _consumeEmojiCluster(scalars, index);
      if (nextIndex == index) {
        return null;
      }
      emojiCount++;
      if (emojiCount > 3) {
        return null;
      }
      index = nextIndex;
    }

    if (emojiCount == 0) {
      return null;
    }
    return MessageEmojiPresentation._(emojiCount);
  }

  static int _consumeEmojiCluster(List<int> scalars, int start) {
    var index = _consumeEmojiComponent(scalars, start);
    if (index == start) {
      return start;
    }
    while (index < scalars.length && scalars[index] == 0x200D) {
      final nextIndex = _consumeEmojiComponent(scalars, index + 1);
      if (nextIndex == index + 1) {
        return start;
      }
      index = nextIndex;
    }
    return index;
  }

  static int _consumeEmojiComponent(List<int> scalars, int start) {
    if (start >= scalars.length) {
      return start;
    }
    final scalar = scalars[start];

    if (_isKeycapBase(scalar)) {
      var index = start + 1;
      if (index < scalars.length && scalars[index] == 0xFE0F) {
        index++;
      }
      if (index < scalars.length && scalars[index] == 0x20E3) {
        return index + 1;
      }
      return start;
    }

    if (_isRegionalIndicator(scalar)) {
      if (start + 1 < scalars.length &&
          _isRegionalIndicator(scalars[start + 1])) {
        return start + 2;
      }
      return start;
    }

    if (!_isEmojiBase(scalar)) {
      return start;
    }

    var index = start + 1;
    while (index < scalars.length) {
      final next = scalars[index];
      if (next == 0xFE0F || _isSkinTone(next) || _isTagScalar(next)) {
        index++;
        continue;
      }
      break;
    }
    return index;
  }

  static bool _isWhitespace(int scalar) =>
      scalar == 0x20 || scalar == 0x09 || scalar == 0x0A || scalar == 0x0D;

  static bool _isKeycapBase(int scalar) =>
      scalar == 0x23 || scalar == 0x2A || (scalar >= 0x30 && scalar <= 0x39);

  static bool _isRegionalIndicator(int scalar) =>
      scalar >= 0x1F1E6 && scalar <= 0x1F1FF;

  static bool _isSkinTone(int scalar) => scalar >= 0x1F3FB && scalar <= 0x1F3FF;

  static bool _isTagScalar(int scalar) =>
      scalar >= 0xE0020 && scalar <= 0xE007F;

  static bool _isEmojiBase(int scalar) {
    if (scalar == 0x00A9 ||
        scalar == 0x00AE ||
        scalar == 0x203C ||
        scalar == 0x2049 ||
        scalar == 0x2122 ||
        scalar == 0x2139 ||
        scalar == 0x3030 ||
        scalar == 0x303D ||
        scalar == 0x3297 ||
        scalar == 0x3299) {
      return true;
    }
    return (scalar >= 0x2194 && scalar <= 0x21AA) ||
        (scalar >= 0x2300 && scalar <= 0x23FF) ||
        (scalar >= 0x2460 && scalar <= 0x27BF) ||
        (scalar >= 0x2934 && scalar <= 0x2935) ||
        (scalar >= 0x2B05 && scalar <= 0x2B55) ||
        (scalar >= 0x1F000 && scalar <= 0x1FAFF);
  }
}

class MessageAnimatedEmojiText extends StatelessWidget {
  final String text;
  final int emojiCount;

  const MessageAnimatedEmojiText({
    super.key,
    required this.text,
    required this.emojiCount,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = switch (emojiCount) {
      1 => 72.0,
      2 => 60.0,
      _ => 52.0,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            height: 1,
            letterSpacing: -0.8,
            shadows: [
              Shadow(
                color: AppTheme.accent.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
