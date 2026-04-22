import 'package:flutter/material.dart';

class SwipeDeleteTile extends StatefulWidget {
  final Widget foreground;
  final Future<bool> Function() onDeleteRequested;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? background;
  final Widget Function(VoidCallback onDeleteTap)? backgroundBuilder;
  final BorderRadius borderRadius;
  final double actionWidth;

  const SwipeDeleteTile({
    super.key,
    required this.foreground,
    required this.onDeleteRequested,
    this.onTap,
    this.onLongPress,
    this.background,
    this.backgroundBuilder,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.actionWidth = 92,
  });

  @override
  State<SwipeDeleteTile> createState() => _SwipeDeleteTileState();
}

class _SwipeDeleteTileState extends State<SwipeDeleteTile> {
  double _dragOffset = 0;
  bool _opened = false;
  bool _deleting = false;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final next = (_dragOffset + details.delta.dx).clamp(-widget.actionWidth, 0.0);
    if (next == _dragOffset) {
      return;
    }
    setState(() {
      _dragOffset = next;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldOpen = velocity < -220 || _dragOffset <= -widget.actionWidth * 0.5;
    setState(() {
      _opened = shouldOpen;
      _dragOffset = shouldOpen ? -widget.actionWidth : 0;
    });
  }

  void _handleTap() {
    if (_opened || _dragOffset < 0) {
      setState(() {
        _opened = false;
        _dragOffset = 0;
      });
      return;
    }
    widget.onTap?.call();
  }

  void _closeSwipe() {
    if (!mounted) {
      return;
    }
    setState(() {
      _opened = false;
      _dragOffset = 0;
    });
  }

  Future<void> _handleDeletePressed() async {
    if (_deleting) {
      return;
    }
    _deleting = true;
    try {
      final deleted = await widget.onDeleteRequested();
      if (deleted) {
        _closeSwipe();
      } else {
        _closeSwipe();
      }
    } catch (_) {
      _closeSwipe();
    } finally {
      _deleting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final background =
        widget.backgroundBuilder?.call(_handleDeletePressed) ??
        widget.background ??
        Card(
          color: Colors.red.shade500,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: widget.actionWidth,
              child: IconButton(
                onPressed: _handleDeletePressed,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Удалить',
              ),
            ),
          ),
        );

    return Stack(
      children: [
        Positioned.fill(child: background),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_dragOffset, 0, 0),
          child: GestureDetector(
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            onHorizontalDragEnd: _handleHorizontalDragEnd,
            behavior: HitTestBehavior.translucent,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: widget.borderRadius,
                onTap: _handleTap,
                onLongPress: widget.onLongPress,
                child: widget.foreground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
