import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

class AvatarCropScreen extends StatefulWidget {
  final Uint8List sourceBytes;

  const AvatarCropScreen({super.key, required this.sourceBytes});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  ui.Image? _image;
  bool _busy = true;
  String? _error;

  Matrix4? _transform;
  Matrix4? _gestureStartTransform;
  Offset? _gestureStartFocalLocal;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.sourceBytes);
      final frame = await codec.getNextFrame();
      _image = frame.image;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final image = _image;
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null || image == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.crop)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _error == null
                  ? strings.imageLoadError
                  : strings.imageOpenError(_error!),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.cropAvatar)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cropSize = math.min(
            constraints.maxWidth - 28,
            constraints.maxHeight - 180,
          );
          _ensureInitialTransform(image: image, cropSize: cropSize);

          final current = _clampTransform(
            _transform!,
            image: image,
            cropSize: cropSize,
          );
          if (!_matrixEquals(_transform!, current)) {
            _transform = current;
          }

          return Column(
            children: [
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  width: cropSize,
                  height: cropSize,
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _gestureStartTransform = _transform!.clone();
                      _gestureStartFocalLocal = details.localFocalPoint;
                    },
                    onScaleUpdate: (details) {
                      final start = _gestureStartTransform;
                      final startFocal = _gestureStartFocalLocal;
                      if (start == null || startFocal == null) {
                        return;
                      }

                      final next = _composeScaleAndPan(
                        startTransform: start,
                        startFocalLocal: startFocal,
                        currentFocalLocal: details.localFocalPoint,
                        scaleDelta: details.scale,
                      );

                      setState(() {
                        _transform = _clampTransform(
                          next,
                          image: image,
                          cropSize: cropSize,
                        );
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _AvatarImagePainter(
                            image: image,
                            transform: _transform!,
                          ),
                        ),
                        const CustomPaint(painter: _AvatarCropOverlayPainter()),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  strings.avatarCropInstruction,
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _applyCrop(image, cropSize),
                    child: Text(strings.apply),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Matrix4 _composeScaleAndPan({
    required Matrix4 startTransform,
    required Offset startFocalLocal,
    required Offset currentFocalLocal,
    required double scaleDelta,
  }) {
    final normalizedScale = scaleDelta.clamp(0.2, 8.0);

    final next = Matrix4.identity()
      ..translateByDouble(currentFocalLocal.dx, currentFocalLocal.dy, 0, 1)
      ..scaleByDouble(normalizedScale, normalizedScale, 1, 1)
      ..translateByDouble(-startFocalLocal.dx, -startFocalLocal.dy, 0, 1)
      ..multiply(startTransform);

    return next;
  }

  Future<void> _applyCrop(ui.Image image, double cropSize) async {
    final transform = _clampTransform(
      _transform!,
      image: image,
      cropSize: cropSize,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const outSize = 320.0;
    final outScale = outSize / cropSize;
    final outTransform = Matrix4.identity()
      ..scaleByDouble(outScale, outScale, 1, 1)
      ..multiply(transform);

    canvas.save();
    canvas.transform(outTransform.storage);
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();

    final rendered = await recorder.endRecording().toImage(
      outSize.toInt(),
      outSize.toInt(),
    );
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || bytes == null) {
      return;
    }
    Navigator.of(context).pop<Uint8List>(bytes.buffer.asUint8List());
  }

  void _ensureInitialTransform({
    required ui.Image image,
    required double cropSize,
  }) {
    if (_transform != null) {
      return;
    }

    final baseScale = _baseScale(image: image, cropSize: cropSize);
    final tx = (cropSize - image.width * baseScale) / 2;
    final ty = (cropSize - image.height * baseScale) / 2;

    _transform = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(baseScale, baseScale, 1, 1);
  }

  Matrix4 _clampTransform(
    Matrix4 transform, {
    required ui.Image image,
    required double cropSize,
  }) {
    var next = transform.clone();

    final minScale = _baseScale(image: image, cropSize: cropSize);
    final maxScale = minScale * 32.0;
    final currentScale = _matrixScale(next);
    if (currentScale < minScale || currentScale > maxScale) {
      final target = currentScale < minScale ? minScale : maxScale;
      final factor = target / currentScale;
      final center = Offset(cropSize / 2, cropSize / 2);
      next = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(factor, factor, 1, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1)
        ..multiply(next);
    }

    final bounds = _transformedImageBounds(next, image);
    var dx = 0.0;
    var dy = 0.0;

    final width = bounds.width;
    if (width <= cropSize) {
      dx = (cropSize - width) / 2 - bounds.left;
    } else {
      if (bounds.left > 0) {
        dx -= bounds.left;
      }
      if (bounds.right < cropSize) {
        dx += cropSize - bounds.right;
      }
    }

    final height = bounds.height;
    if (height <= cropSize) {
      dy = (cropSize - height) / 2 - bounds.top;
    } else {
      if (bounds.top > 0) {
        dy -= bounds.top;
      }
      if (bounds.bottom < cropSize) {
        dy += cropSize - bounds.bottom;
      }
    }

    if (dx != 0 || dy != 0) {
      next = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..multiply(next);
    }

    return next;
  }

  Rect _transformedImageBounds(Matrix4 matrix, ui.Image image) {
    final points = <Offset>[
      MatrixUtils.transformPoint(matrix, const Offset(0, 0)),
      MatrixUtils.transformPoint(matrix, Offset(image.width.toDouble(), 0)),
      MatrixUtils.transformPoint(
        matrix,
        Offset(image.width.toDouble(), image.height.toDouble()),
      ),
      MatrixUtils.transformPoint(matrix, Offset(0, image.height.toDouble())),
    ];

    var left = points.first.dx;
    var right = points.first.dx;
    var top = points.first.dy;
    var bottom = points.first.dy;

    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _baseScale({required ui.Image image, required double cropSize}) {
    final sx = cropSize / image.width;
    final sy = cropSize / image.height;
    return math.min(sx, sy);
  }

  double _matrixScale(Matrix4 matrix) {
    final sx = math.sqrt(
      matrix.entry(0, 0) * matrix.entry(0, 0) +
          matrix.entry(1, 0) * matrix.entry(1, 0),
    );
    final sy = math.sqrt(
      matrix.entry(0, 1) * matrix.entry(0, 1) +
          matrix.entry(1, 1) * matrix.entry(1, 1),
    );
    return (sx + sy) / 2;
  }

  bool _matrixEquals(Matrix4 a, Matrix4 b, {double eps = 1e-6}) {
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > eps) {
        return false;
      }
    }
    return true;
  }
}

class _AvatarCropOverlayPainter extends CustomPainter {
  const _AvatarCropOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final outerRect = Offset.zero & size;

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outerRect)
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AvatarImagePainter extends CustomPainter {
  final ui.Image image;
  final Matrix4 transform;

  const _AvatarImagePainter({required this.image, required this.transform});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.transform(transform.storage);
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AvatarImagePainter oldDelegate) {
    if (oldDelegate.image != image) {
      return true;
    }
    for (var i = 0; i < 16; i++) {
      if ((oldDelegate.transform.storage[i] - transform.storage[i]).abs() >
          1e-6) {
        return true;
      }
    }
    return false;
  }
}
