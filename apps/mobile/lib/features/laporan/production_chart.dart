import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_analytics.dart';

// Synthetic presentation fixture; no production calculation is performed here.
const _demoDays = [
  _ChartDay(16, 40, 5.8, 24, 10, 6),
  _ChartDay(17, 50, 6.4, 30, 12, 8),
  _ChartDay(18, 45, 6.0, 27, 11, 7),
  _ChartDay(19, 60, 7.1, 36, 15, 9),
  _ChartDay(20, 70, 7.6, 42, 18, 10),
  _ChartDay(21, 45, 6.8, 27, 11, 7),
  _ChartDay(22, 50, 7.3, 30, 13, 7),
];
const _barColor = Color(0xFFD9E4DD);
const _gradeB = Color(0xFFD3A734);
const _gradeC = Color(0xFFDCE6DE);

class _ChartDay {
  const _ChartDay(this.day, this.kg, this.rendemen, this.a, this.b, this.c);
  final int day;
  final double kg;
  final double rendemen;
  final double a;
  final double b;
  final double c;
}

class ProductionChart extends StatefulWidget {
  const ProductionChart({required this.analytics, super.key});
  final DemoAnalytics analytics;

  @override
  State<ProductionChart> createState() => _ProductionChartState();
}

class _ProductionChartState extends State<ProductionChart> {
  int? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final grade = widget.analytics.variant == ProductionVariant.grade;
    final days = _demoDays
        .where(
          (day) =>
              widget.analytics.dateFilter?.contains(
                DateTime(2026, 10, day.day),
              ) ??
              true,
        )
        .toList();
    final selected = days.indexWhere((day) => day.day == _selectedDay);
    return NiraOutline(
      Padding(
        padding: const EdgeInsets.all(NiraSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Gula final per hari (Kg)',
                    style: niraText(NiraType.body, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: NiraSpace.sm),
                PopupMenuButton<ProductionVariant>(
                  tooltip: 'Jenis grafik',
                  initialValue: widget.analytics.variant,
                  onSelected: (variant) {
                    setState(() => _selectedDay = null);
                    widget.analytics.setVariant(variant);
                  },
                  color: niraPaper,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(niraRadius),
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: ProductionVariant.rendemen,
                      child: Text('Rendemen'),
                    ),
                    PopupMenuItem(
                      value: ProductionVariant.grade,
                      child: Text('Grade'),
                    ),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: NiraSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F6F1),
                      border: Border.all(color: niraLine),
                      borderRadius: BorderRadius.circular(niraRadius),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grade ? 'Grade' : 'Rendemen',
                          style: niraText(
                            NiraType.caption,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: NiraSpace.xs),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: niraGreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NiraSpace.md),
            Wrap(
              spacing: NiraSpace.md,
              runSpacing: NiraSpace.sm,
              children: grade
                  ? [
                      _legend('Grade A', niraGreen),
                      _legend('Grade B', _gradeB),
                      _legend('Grade C', _gradeC),
                      _legend('Total (kg)', niraGreen, line: true),
                    ]
                  : [
                      _legend('Gula final (kg)', _barColor),
                      _legend('Rendemen (%)', niraGreen, line: true),
                    ],
            ),
            const SizedBox(height: NiraSpace.sm),
            if (days.isEmpty)
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
                  final width = constraints.maxWidth;
                  final plot = Rect.fromLTRB(
                    32,
                    32,
                    width - (grade ? 8 : 30),
                    194,
                  );
                  void select(Offset position) {
                    if (!plot.contains(position)) return;
                    final index =
                        ((position.dx - plot.left) / plot.width * days.length)
                            .floor()
                            .clamp(0, days.length - 1);
                    if (_selectedDay != days[index].day)
                      setState(() => _selectedDay = days[index].day);
                  }

                  return Semantics(
                    label: grade
                        ? 'Grafik batang grade A, B, C dan garis total gula dalam kilogram.'
                        : 'Grafik batang gula dalam kilogram dan garis rendemen dalam persen.',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.precise,
                      onHover: (event) => select(event.localPosition),
                      onExit: (_) => setState(() => _selectedDay = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (event) => select(event.localPosition),
                        onHorizontalDragUpdate: (event) =>
                            select(event.localPosition),
                        child: SizedBox(
                          key: const ValueKey('production-chart-plot'),
                          height: 228,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ProductionPainter(
                                    days: days,
                                    grade: grade,
                                    selected: selected,
                                    plot: plot,
                                    textDirection: Directionality.of(context),
                                  ),
                                ),
                              ),
                              if (selected >= 0)
                                Positioned(
                                  left:
                                      ((plot.left +
                                                  (selected + .5) *
                                                      plot.width /
                                                      days.length) -
                                              86)
                                          .clamp(
                                            0.0,
                                            math.max(0.0, width - 172),
                                          ),
                                  top: 0,
                                  width: math.min(172, width),
                                  child: IgnorePointer(
                                    child: _detail(days[selected], grade),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            Text(
              'Oktober 2026 · Data simulasi',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
            const SizedBox(height: NiraSpace.xs),
            Text(
              'Arahkan kursor atau ketuk grafik untuk detail.',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color, {bool line = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: line ? 18 : 10,
        height: line ? 3 : 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: NiraSpace.xs),
      Text(label, style: niraText(NiraType.caption, color: niraLeaf)),
    ],
  );

  Widget _detail(_ChartDay day, bool grade) => Container(
    key: const ValueKey('production-chart-detail'),
    padding: const EdgeInsets.all(NiraSpace.sm),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${day.day} Oktober 2026',
          style: niraText(
            NiraType.caption,
            color: Colors.white,
            weight: FontWeight.w600,
          ),
        ),
        Text(
          'Gula final: ${day.kg.toInt()} kg',
          style: niraText(NiraType.caption, color: Colors.white),
        ),
        Text(
          grade
              ? 'A: ${day.a.toInt()} · B: ${day.b.toInt()} · C: ${day.c.toInt()} kg'
              : 'Rendemen: ${day.rendemen.toStringAsFixed(1).replaceAll('.', ',')}%',
          style: niraText(NiraType.caption, color: niraYellow),
        ),
      ],
    ),
  );
}

class _ProductionPainter extends CustomPainter {
  const _ProductionPainter({
    required this.days,
    required this.grade,
    required this.selected,
    required this.plot,
    required this.textDirection,
  });
  final List<_ChartDay> days;
  final bool grade;
  final int selected;
  final Rect plot;
  final TextDirection textDirection;

  void _text(
    Canvas canvas,
    String value,
    Offset center, {
    Color color = niraLeaf,
  }) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: niraText(10, color: color, height: 1.2),
      ),
      textDirection: textDirection,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = niraLine
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final y = plot.bottom - tick * plot.height / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, '${tick * 25}', Offset(plot.left - 18, y));
      if (!grade) _text(canvas, '${tick * 2}', Offset(plot.right + 17, y));
    }
    _text(canvas, 'kg', Offset(plot.left - 18, plot.top - 18));
    if (!grade) _text(canvas, '%', Offset(plot.right + 17, plot.top - 18));
    final slot = plot.width / days.length;
    final barWidth = math.min(19.0, slot * .48);
    final points = <Offset>[];
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final x = plot.left + slot * (i + .5);
      if (i == selected)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - slot / 2 + 1, plot.top, slot - 2, plot.height),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0x0D174B35),
        );
      if (grade) {
        var bottom = plot.bottom;
        for (final (value, color) in [
          (day.c, _gradeC),
          (day.b, _gradeB),
          (day.a, niraGreen),
        ]) {
          final h = value / 100 * plot.height;
          canvas.drawRect(
            Rect.fromLTWH(x - barWidth / 2, bottom - h, barWidth, h),
            Paint()..color = color,
          );
          bottom -= h;
        }
      } else {
        final h = day.kg / 100 * plot.height;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, plot.bottom - h, barWidth, h),
            const Radius.circular(4),
          ),
          Paint()..color = i == selected ? niraLeaf : _barColor,
        );
      }
      points.add(
        Offset(
          x,
          plot.bottom - (grade ? day.kg / 100 : day.rendemen / 8) * plot.height,
        ),
      );
      _text(canvas, '${day.day}', Offset(x, plot.bottom + 16));
    }
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = niraGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        points[i],
        i == selected ? 5 : 3,
        Paint()..color = niraGreen,
      );
      canvas.drawCircle(
        points[i],
        i == selected ? 2.5 : 1.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProductionPainter old) =>
      old.grade != grade ||
      old.selected != selected ||
      old.plot != plot ||
      !listEquals(old.days, days);
}
