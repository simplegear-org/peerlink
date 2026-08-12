import 'package:flutter/material.dart';

class ChatScreenBackSwipeCoordinator {
  final void Function() dismissKeyboardIfInputEmpty;
  final VoidCallback pop;

  Offset? _start;
  DateTime? _startedAt;
  double _dx = 0;
  double _dy = 0;

  ChatScreenBackSwipeCoordinator({
    required this.dismissKeyboardIfInputEmpty,
    required this.pop,
  });

  void handlePointerDown(PointerDownEvent event) {
    dismissKeyboardIfInputEmpty();
    _start = event.position;
    _startedAt = DateTime.now();
    _dx = 0;
    _dy = 0;
  }

  void handlePointerMove(PointerEvent event) {
    final start = _start;
    if (start == null) {
      return;
    }
    final delta = event.position - start;
    _dx = delta.dx;
    _dy = delta.dy;
  }

  void handlePointerUp(
    PointerUpEvent event, {
    required double minDistance,
    required double fastMinDistance,
    required double directionRatio,
    required double minVelocity,
  }) {
    handlePointerMove(event);
    _complete(
      minDistance: minDistance,
      fastMinDistance: fastMinDistance,
      directionRatio: directionRatio,
      minVelocity: minVelocity,
    );
  }

  void handlePointerCancel(PointerCancelEvent event) {
    _reset();
  }

  void _complete({
    required double minDistance,
    required double fastMinDistance,
    required double directionRatio,
    required double minVelocity,
  }) {
    final startedAt = _startedAt;
    final elapsedMs = startedAt == null
        ? 1
        : DateTime.now().difference(startedAt).inMilliseconds.clamp(1, 100000);
    final horizontalVelocity = _dx / (elapsedMs / 1000);
    final isMostlyRightward = _dx > 0 && _dx.abs() > _dy.abs() * directionRatio;
    final hasEnoughDistance = _dx > minDistance;
    final isFastRightward =
        _dx > fastMinDistance && horizontalVelocity > minVelocity;
    final shouldPop =
        isMostlyRightward && (hasEnoughDistance || isFastRightward);
    _reset();
    if (!shouldPop) {
      return;
    }
    pop();
  }

  void _reset() {
    _start = null;
    _startedAt = null;
    _dx = 0;
    _dy = 0;
  }
}
