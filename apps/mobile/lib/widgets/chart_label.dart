import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';
import 'adaptive_value.dart';

String chartTick(double value) {
  final text = value.toStringAsFixed(0);
  return value.abs() < 10000 ? text : compactDisplayValue(text, short: true);
}

/// Constrain chart labels to their axis or bar slot, including negative values.
void paintChartLabel(
  Canvas canvas,
  String value,
  Rect bounds, {
  required TextDirection direction,
  required TextScaler scaler,
  double fontSize = 11,
  bool bold = false,
}) {
  if (bounds.width < scaler.scale(fontSize) * 2 || bounds.height <= 0) return;
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: niraText(
        fontSize,
        color: niraLeaf,
        height: 1.2,
        weight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: bounds.width);
  if (painter.computeLineMetrics().any((line) => line.width > bounds.width)) {
    painter.dispose();
    return;
  }
  painter.paint(
    canvas,
    Offset(
      bounds.left + (bounds.width - painter.width) / 2,
      bounds.top + (bounds.height - painter.height) / 2,
    ),
  );
  painter.dispose();
}
