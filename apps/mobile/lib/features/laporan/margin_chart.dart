import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/chart_growth.dart';
import 'demo_analytics.dart';
import 'report_date_button.dart';

class MarginChart extends StatefulWidget {
  const MarginChart({required this.rows, required this.onFilter, super.key});
  final List<AnalyticsRow> rows;
  final VoidCallback onFilter;

  @override
  State<MarginChart> createState() => _MarginChartState();
}

class _MarginChartState extends State<MarginChart> {
  final _scroll = ScrollController();
  int? _selected;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(NiraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Margin per kloter (1000)',
                  style: niraText(NiraType.body, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: NiraSpace.sm),
              ReportDateButton(onPressed: widget.onFilter),
            ],
          ),
          const SizedBox(height: NiraSpace.sm),
          if (widget.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'Belum ada data grafik pada periode ini.',
                textAlign: TextAlign.center,
                style: niraText(NiraType.caption, color: niraLeaf),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final step = math.max(
                  68.0,
                  MediaQuery.textScalerOf(context).scale(11) * 5.5,
                );
                final width = math.max(
                  constraints.maxWidth,
                  widget.rows.length * step + 48,
                );
                final plot = Rect.fromLTRB(36, 24, width - 8, 148);
                void select(Offset point) {
                  if (!plot.contains(point)) return;
                  final index =
                      ((point.dx - plot.left) / plot.width * widget.rows.length)
                          .floor()
                          .clamp(0, widget.rows.length - 1);
                  if (_selected != index) setState(() => _selected = index);
                }

                return Scrollbar(
                  controller: _scroll,
                  thumbVisibility: width > constraints.maxWidth,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: Semantics(
                      label:
                          'Margin per kloter dalam ribuan rupiah. ${widget.rows.map((row) => '${row.supplier}: ${row.value}').join(', ')}',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.precise,
                        onHover: (event) => select(event.localPosition),
                        onExit: (_) => setState(() => _selected = null),
                        child: GestureDetector(
                          onTapUp: (event) => select(event.localPosition),
                          child: SizedBox(
                            key: const ValueKey('margin-chart-plot'),
                            width: width,
                            height: 186,
                            child: ChartGrowth(
                              replayKey: widget.rows
                                  .map((row) => row.code)
                                  .join(','),
                              builder: (context, progress) => CustomPaint(
                                painter: _MarginPainter(
                                  rows: widget.rows,
                                  plot: plot,
                                  progress: progress,
                                  selected: _selected,
                                  textDirection: Directionality.of(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

class _MarginPainter extends CustomPainter {
  const _MarginPainter({
    required this.rows,
    required this.plot,
    required this.progress,
    required this.selected,
    required this.textDirection,
  });
  final List<AnalyticsRow> rows;
  final Rect plot;
  final double progress;
  final int? selected;
  final TextDirection textDirection;

  double _thousands(AnalyticsRow row) =>
      double.parse(row.value.replaceAll(RegExp(r'[^\d-]'), '')) / 1000;

  void _text(Canvas canvas, String value, Offset center, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: niraText(
          11,
          height: 1.2,
          weight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = rows.map(_thousands).toList();
    final maximum = math.max(
      200.0,
      (values.reduce(math.max) / 200).ceil() * 200.0,
    );
    final minimum = math.min(
      0.0,
      (values.reduce(math.min) / 200).floor() * 200.0,
    );
    double yFor(double value) =>
        plot.bottom - (value - minimum) / (maximum - minimum) * plot.height;
    final baseline = yFor(0);
    for (var i = 0; i <= 2; i++) {
      final value = minimum + (maximum - minimum) * i / 2;
      final y = yFor(value);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = niraLine
          ..strokeWidth = 1,
      );
      _text(canvas, value.toInt().toString(), Offset(plot.left - 20, y));
    }
    final slot = plot.width / rows.length;
    for (var i = 0; i < rows.length; i++) {
      final x = plot.left + (i + .5) * slot;
      final tip = yFor(values[i] * progress);
      final w = math.min(36.0, slot * .55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - w / 2,
            math.min(tip, baseline),
            w,
            (tip - baseline).abs(),
          ),
          const Radius.circular(3),
        ),
        Paint()..color = i == selected ? niraGreenHover : niraGreen,
      );
      _text(
        canvas,
        values[i].abs() < 1 && values[i] != 0
            ? values[i].toStringAsFixed(3).replaceAll('.', ',')
            : values[i].toInt().toString(),
        Offset(x, tip + (values[i] < 0 ? 10 : -10)),
        bold: true,
      );
      _text(canvas, rows[i].supplier, Offset(x, plot.bottom + 18));
    }
  }

  @override
  bool shouldRepaint(covariant _MarginPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.rows != rows ||
      old.plot != plot;
}
