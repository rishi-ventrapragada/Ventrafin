import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PatternPadState { idle, error, success }

/// Android-style 3x3 unlock pattern. Dots are numbered 0-8, row by row.
/// Drag through the dots; lifting the finger reports the sequence. As on
/// Android, passing straight over an unvisited dot (e.g. 0 -> 2 over 1)
/// includes it.
class PatternPad extends StatefulWidget {
  const PatternPad({
    super.key,
    required this.onComplete,
    this.state = PatternPadState.idle,
    this.enabled = true,
    this.size = 280,
  });

  final ValueChanged<List<int>> onComplete;
  final PatternPadState state;
  final bool enabled;
  final double size;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> _dots = [];
  Offset? _finger;

  double get _cell => widget.size / 3;

  Offset _center(int i) => Offset((i % 3 + 0.5) * _cell, (i ~/ 3 + 0.5) * _cell);

  int? _hit(Offset p) {
    for (var i = 0; i < 9; i++) {
      if ((p - _center(i)).distance <= _cell * 0.32) return i;
    }
    return null;
  }

  void _add(int dot) {
    if (_dots.contains(dot)) return;
    if (_dots.isNotEmpty) {
      final last = _dots.last;
      // Midpoint of two dots in the same row/column/diagonal, two apart.
      final r1 = last ~/ 3, c1 = last % 3, r2 = dot ~/ 3, c2 = dot % 3;
      if ((r1 + r2).isEven && (c1 + c2).isEven) {
        final mid = ((r1 + r2) ~/ 2) * 3 + (c1 + c2) ~/ 2;
        if (mid != last && mid != dot && !_dots.contains(mid)) _dots.add(mid);
      }
    }
    _dots.add(dot);
    HapticFeedback.selectionClick();
  }

  void _start(Offset p) {
    setState(() {
      _dots.clear();
      _finger = p;
      final hit = _hit(p);
      if (hit != null) _add(hit);
    });
  }

  void _move(Offset p) {
    setState(() {
      _finger = p;
      final hit = _hit(p);
      if (hit != null) _add(hit);
    });
  }

  void _end() {
    final result = List<int>.of(_dots);
    setState(() {
      _finger = null;
      _dots.clear();
    });
    if (result.isNotEmpty) widget.onComplete(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (widget.state) {
      PatternPadState.error => scheme.error,
      PatternPadState.success => Colors.green.shade700,
      PatternPadState.idle => scheme.primary,
    };
    return Semantics(
      label: 'Unlock pattern: drag through at least 4 of the 9 dots',
      child: SizedBox.square(
        dimension: widget.size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: widget.enabled ? (d) => _start(d.localPosition) : null,
          onPanUpdate: widget.enabled ? (d) => _move(d.localPosition) : null,
          onPanEnd: widget.enabled ? (_) => _end() : null,
          onPanCancel: widget.enabled ? _end : null,
          child: CustomPaint(
            painter: _PatternPainter(
              dots: List.of(_dots),
              finger: _finger,
              center: _center,
              cell: _cell,
              lineColor: color,
              dotColor: widget.enabled ? scheme.onSurfaceVariant : scheme.outlineVariant,
              activeColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dots,
    required this.finger,
    required this.center,
    required this.cell,
    required this.lineColor,
    required this.dotColor,
    required this.activeColor,
  });

  final List<int> dots;
  final Offset? finger;
  final Offset Function(int) center;
  final double cell;
  final Color lineColor;
  final Color dotColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < dots.length; i++) {
      canvas.drawLine(center(dots[i - 1]), center(dots[i]), line);
    }
    if (finger != null && dots.isNotEmpty) canvas.drawLine(center(dots.last), finger!, line);

    for (var i = 0; i < 9; i++) {
      final active = dots.contains(i);
      canvas.drawCircle(center(i), active ? cell * 0.13 : cell * 0.07, Paint()..color = active ? activeColor : dotColor);
      if (active) {
        canvas.drawCircle(
          center(i),
          cell * 0.24,
          Paint()
            ..color = activeColor.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => true;
}
