import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/chart_growth.dart';
import '../../widgets/chart_label.dart';
import '../../widgets/adaptive_value.dart';
import 'demo_analytics.dart';
import 'report_date_button.dart';

/// Chart values are expressed in thousands of rupiah.
String marginChartLabel(double thousands) =>
    thousands.abs() < 1 && thousands != 0
    ? thousands.toStringAsFixed(3).replaceAll('.', ',')
    : chartTick(thousands);

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
                final scaler = MediaQuery.textScalerOf(context);
                final left = math.max(52.0, scaler.scale(11) * 6);
                final plot = Rect.fromLTRB(
                  left,
                  scaler.scale(24),
                  width - 8,
                  scaler.scale(148),
                );
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
                            height: scaler.scale(210),
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
                                  scaler: scaler,
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
          if (_selected != null && _selected! < widget.rows.length) ...[
            const SizedBox(height: NiraSpace.sm),
            Text(
              widget.rows[_selected!].supplier,
              style: niraText(NiraType.caption),
            ),
            NiraValue(
              widget.rows[_selected!].value,
              label: 'Margin kloter',
              abbreviate: false,
              style: niraText(NiraType.body, weight: FontWeight.w600),
            ),
          ],
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
    required this.scaler,
  });
  final List<AnalyticsRow> rows;
  final Rect plot;
  final double progress;
  final int? selected;
  final TextDirection textDirection;
  final TextScaler scaler;

  double _thousands(AnalyticsRow row) =>
      double.parse(row.value.replaceAll(RegExp(r'[^\d-]'), '')) / 1000;

  void _text(Canvas canvas, String value, Rect bounds, {bool bold = false}) =>
      paintChartLabel(
        canvas,
        value,
        bounds,
        direction: textDirection,
        scaler: scaler,
        bold: bold,
      );

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
    final range = maximum - minimum;
    final zero = plot.bottom + minimum / range * plot.height;
    for (var i = 0; i <= 2; i++) {
      final y = plot.bottom - plot.height * i / 2;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = niraLine
          ..strokeWidth = 1,
      );
      _text(
        canvas,
        chartTick(minimum + range * i / 2),
        Rect.fromLTWH(0, y - scaler.scale(9), plot.left - 6, scaler.scale(18)),
      );
    }
    final slot = plot.width / rows.length;
    for (var i = 0; i < rows.length; i++) {
      final x = plot.left + (i + .5) * slot;
      final h = values[i] / range * plot.height * progress;
      final w = math.min(36.0, slot * .55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - w / 2, math.min(zero, zero - h), w, h.abs()),
          const Radius.circular(3),
        ),
        Paint()..color = i == selected ? niraGreenHover : niraGreen,
      );
      _text(
        canvas,
        marginChartLabel(values[i]),
        Rect.fromLTWH(
          plot.left + i * slot,
          (zero - h + (h < 0 ? scaler.scale(2) : -scaler.scale(18))).clamp(
            0.0,
            plot.bottom + scaler.scale(2),
          ),
          slot,
          scaler.scale(18),
        ),
        bold: true,
      );
      _text(
        canvas,
        rows[i].supplier,
        Rect.fromLTWH(
          plot.left + i * slot,
          plot.bottom + scaler.scale(30),
          slot,
          scaler.scale(20),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarginPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.rows != rows ||
      old.plot != plot ||
      old.scaler != scaler;
}
