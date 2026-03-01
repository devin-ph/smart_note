import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class _StrokePoint {
  final Offset offset;
  final Color color;
  final double size;

  const _StrokePoint({
    required this.offset,
    required this.color,
    required this.size,
  });
}

class _Stroke {
  final List<_StrokePoint> points;

  _Stroke(this.points);
}

class DrawingPadScreen extends StatefulWidget {
  const DrawingPadScreen({super.key});

  @override
  State<DrawingPadScreen> createState() => _DrawingPadScreenState();
}

class _DrawingPadScreenState extends State<DrawingPadScreen> {
  final List<_Stroke> _strokes = [];
  List<_StrokePoint> _activeStroke = [];

  Color _selectedColor = const Color(0xFF1F2937);
  double _strokeSize = 3.5;

  void _startStroke(Offset position) {
    setState(() {
      _activeStroke = [
        _StrokePoint(
          offset: position,
          color: _selectedColor,
          size: _strokeSize,
        ),
      ];
    });
  }

  void _appendStroke(Offset position) {
    setState(() {
      _activeStroke.add(
        _StrokePoint(
          offset: position,
          color: _selectedColor,
          size: _strokeSize,
        ),
      );
    });
  }

  void _endStroke() {
    if (_activeStroke.isEmpty) {
      return;
    }

    setState(() {
      _strokes.add(_Stroke(List<_StrokePoint>.from(_activeStroke)));
      _activeStroke = [];
    });
  }

  void _undoStroke() {
    if (_strokes.isEmpty) {
      return;
    }

    setState(() {
      _strokes.removeLast();
    });
  }

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _activeStroke = [];
    });
  }

  Future<void> _saveDrawing() async {
    if (_strokes.isEmpty && _activeStroke.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final allStrokes = [
      ..._strokes,
      if (_activeStroke.isNotEmpty)
        _Stroke(List<_StrokePoint>.from(_activeStroke)),
    ];

    const width = 1600.0;
    const height = 1000.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), backgroundPaint);

    for (final stroke in allStrokes) {
      if (stroke.points.length < 2) {
        if (stroke.points.isNotEmpty) {
          final point = stroke.points.first;
          final paint = Paint()
            ..color = point.color
            ..style = PaintingStyle.fill;
          canvas.drawCircle(point.offset, point.size / 2, paint);
        }
        continue;
      }

      for (var i = 0; i < stroke.points.length - 1; i++) {
        final current = stroke.points[i];
        final next = stroke.points[i + 1];

        final paint = Paint()
          ..color = current.color
          ..strokeWidth = current.size
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke;

        canvas.drawLine(current.offset, next.offset, paint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return;
    }

    Navigator.pop(context, byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF1F2937),
      const Color(0xFF1D4ED8),
      const Color(0xFFDC2626),
      const Color(0xFF059669),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vẽ tay'),
        actions: [
          IconButton(
            tooltip: 'Hoàn tác',
            onPressed: _undoStroke,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Xóa hết',
            onPressed: _clearCanvas,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          TextButton.icon(
            onPressed: _saveDrawing,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Lưu'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                ...colors.map(
                  (color) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedColor = color),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == color
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.line_weight_rounded, size: 18),
                Expanded(
                  child: Slider(
                    value: _strokeSize,
                    min: 1.5,
                    max: 8,
                    onChanged: (value) => setState(() => _strokeSize = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  onPanStart: (details) => _startStroke(details.localPosition),
                  onPanUpdate: (details) =>
                      _appendStroke(details.localPosition),
                  onPanEnd: (_) => _endStroke(),
                  child: CustomPaint(
                    painter: _DrawingPainter(
                      strokes: _strokes,
                      activeStroke: _activeStroke,
                    ),
                    child: Container(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter({required this.strokes, required this.activeStroke});

  final List<_Stroke> strokes;
  final List<_StrokePoint> activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final allStrokes = [
      ...strokes,
      if (activeStroke.isNotEmpty) _Stroke(activeStroke),
    ];

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      if (stroke.points.length == 1) {
        final point = stroke.points.first;
        final paint = Paint()
          ..color = point.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point.offset, point.size / 2, paint);
        continue;
      }

      for (var i = 0; i < stroke.points.length - 1; i++) {
        final current = stroke.points[i];
        final next = stroke.points[i + 1];
        final paint = Paint()
          ..color = current.color
          ..strokeWidth = current.size
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
        canvas.drawLine(current.offset, next.offset, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.activeStroke != activeStroke;
  }
}
