import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';

enum QuickActionKind { profit, expenses, recap, help }

/// Small vector pictograms, drawn on one grid so they stay crisp at any DPR.
class QuickActionIcon extends StatelessWidget {
  const QuickActionIcon(this.kind, {this.size = 40, super.key});

  final QuickActionKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _QuickActionPainter(kind)),
    ),
  );
}

class _QuickActionPainter extends CustomPainter {
  const _QuickActionPainter(this.kind);

  final QuickActionKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    switch (kind) {
      case QuickActionKind.profit:
        _calculator(canvas);
      case QuickActionKind.expenses:
        _tag(canvas);
      case QuickActionKind.recap:
        _clipboard(canvas);
      case QuickActionKind.help:
        _headset(canvas);
    }
    canvas.restore();
  }

  Paint _fill(Color color) => Paint()..color = color;

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _roundRect(Canvas canvas, Rect rect, double radius, Color color) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        _fill(color),
      );

  void _calculator(Canvas canvas) {
    _roundRect(canvas, const Rect.fromLTWH(9, 4, 30, 40), 4, niraOchre);
    _roundRect(canvas, const Rect.fromLTWH(12, 7, 24, 12), 2, Colors.white);
    canvas.drawPath(
      Path()
        ..moveTo(16, 15)
        ..lineTo(21, 11)
        ..lineTo(25, 14)
        ..lineTo(32, 9)
        ..moveTo(28, 9)
        ..lineTo(32, 9)
        ..lineTo(32, 12.5),
      _stroke(niraGreen, 2.3),
    );
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        _roundRect(
          canvas,
          Rect.fromLTWH(13 + col * 9, 25 + row * 9, 5, 5),
          1.2,
          Colors.white,
        );
      }
    }
  }

  void _tag(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(7, 6)
        ..quadraticBezierTo(7, 3, 11, 3)
        ..lineTo(24, 3)
        ..quadraticBezierTo(26, 3, 28, 5)
        ..lineTo(44, 23)
        ..quadraticBezierTo(46, 25, 43, 28)
        ..lineTo(27, 44)
        ..quadraticBezierTo(25, 46, 22, 43)
        ..lineTo(5, 25)
        ..quadraticBezierTo(3, 23, 4, 20)
        ..close(),
      _fill(niraOchre),
    );
    canvas.drawCircle(const Offset(13, 12), 3.8, _fill(Colors.white));
    canvas.drawPath(
      Path()
        ..moveTo(43, 28)
        ..lineTo(27, 44)
        ..quadraticBezierTo(25, 46, 24, 43)
        ..lineTo(24, 35)
        ..quadraticBezierTo(24, 28, 31, 28)
        ..close(),
      _fill(niraGreen),
    );
    canvas.drawLine(
      const Offset(19, 23),
      const Offset(27, 15),
      _stroke(niraGreen, 2.7),
    );
    canvas.drawLine(
      const Offset(24, 27),
      const Offset(32, 19),
      _stroke(niraGreen, 2.7),
    );
  }

  void _clipboard(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 9, 32, 35),
        const Radius.circular(4),
      ),
      _stroke(niraOchre, 3.5),
    );
    canvas.drawCircle(const Offset(24, 6), 5, _fill(niraGreen));
    _roundRect(canvas, const Rect.fromLTWH(16, 5, 16, 8), 2, niraGreen);
    canvas.drawCircle(const Offset(24, 5), 1.7, _fill(Colors.white));
    for (var row = 0; row < 3; row++) {
      final y = 20.0 + row * 8;
      _roundRect(canvas, Rect.fromLTWH(13, y - 2, 4, 4), .8, niraGold);
      canvas.drawLine(Offset(21, y), Offset(34, y), _stroke(niraGreen, 2.5));
    }
  }

  void _headset(Canvas canvas) {
    canvas.drawArc(
      const Rect.fromLTWH(7, 5, 34, 36),
      math.pi,
      math.pi,
      false,
      _stroke(niraOchre, 3.8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(40, 31)
        ..lineTo(40, 34)
        ..quadraticBezierTo(40, 43, 31, 43)
        ..lineTo(27, 43),
      _stroke(niraOchre, 3.8),
    );
    _roundRect(canvas, const Rect.fromLTWH(4, 22, 9, 15), 4, niraGreen);
    _roundRect(canvas, const Rect.fromLTWH(35, 22, 9, 15), 4, niraGreen);
    _roundRect(canvas, const Rect.fromLTWH(22, 40, 10, 6), 3, niraGreen);
  }

  @override
  bool shouldRepaint(covariant _QuickActionPainter oldDelegate) =>
      oldDelegate.kind != kind;
}
