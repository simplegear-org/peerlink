import 'package:flutter/material.dart';

class RightSwipePopRegion extends StatefulWidget {
  final Widget child;

  const RightSwipePopRegion({super.key, required this.child});

  @override
  State<RightSwipePopRegion> createState() => _RightSwipePopRegionState();
}

class _RightSwipePopRegionState extends State<RightSwipePopRegion> {
  static const double _minDistance = 88;
  static const double _fastMinDistance = 48;
  static const double _directionRatio = 1.15;
  static const double _velocity = 650;

  Offset? _start;
  DateTime? _startedAt;
  double _dx = 0;
  double _dy = 0;

  void _handlePointerDown(PointerDownEvent event) {
    _start = event.position;
    _startedAt = DateTime.now();
    _dx = 0;
    _dy = 0;
  }

  void _handlePointerMove(PointerEvent event) {
    final start = _start;
    if (start == null) {
      return;
    }
    final delta = event.position - start;
    _dx = delta.dx;
    _dy = delta.dy;
  }

  void _handlePointerUp(PointerUpEvent event) {
    _handlePointerMove(event);
    _completeSwipe();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _reset();
  }

  void _completeSwipe() {
    final startedAt = _startedAt;
    final elapsedMs = startedAt == null
        ? 1
        : DateTime.now().difference(startedAt).inMilliseconds.clamp(1, 100000);
    final horizontalVelocity = _dx / (elapsedMs / 1000);
    final isMostlyRightward =
        _dx > 0 && _dx.abs() > _dy.abs() * _directionRatio;
    final hasEnoughDistance = _dx > _minDistance;
    final isFastRightward =
        _dx > _fastMinDistance && horizontalVelocity > _velocity;
    final shouldPop =
        mounted && isMostlyRightward && (hasEnoughDistance || isFastRightward);

    _reset();
    if (!shouldPop) {
      return;
    }
    Navigator.maybePop(context);
  }

  void _reset() {
    _start = null;
    _startedAt = null;
    _dx = 0;
    _dy = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
