import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/chart_growth.dart';
import 'demo_analytics.dart';
import 'report_date_button.dart';

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
const _barColor = niraGreen;
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
  const ProductionChart({required this.analytics, this.onFilter, super.key});
  final DemoAnalytics analytics;
  final VoidCallback? onFilter;

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
                    style: niraText(NiraType.body, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: NiraSpace.sm),
                PopupMenuButton<ProductionVariant>(
                  tooltip: 'Jenis grafik',
                  onSelected: (variant) {
                    setState(() => _selectedDay = null);
                    widget.analytics.setVariant(variant);
                  },
                  color: niraPaper,
                  position: PopupMenuPosition.under,
                  offset: Offset.zero,
                  elevation: 4,
                  shadowColor: const Color(0x33174B35),
                  menuPadding: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(niraRadius),
                    side: const BorderSide(color: niraGreen, width: 1.2),
                  ),
                  itemBuilder: (_) => [
                    for (final variant in [
                      widget.analytics.variant,
                      if (grade)
                        ProductionVariant.rendemen
                      else
                        ProductionVariant.grade,
                    ])
                      PopupMenuItem(
                        key: ValueKey('chart-option-${variant.name}'),
                        value: variant,
                        height: 0,
                        padding: EdgeInsets.zero,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          color: variant == widget.analytics.variant
                              ? niraGreen
                              : niraPaper,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NiraSpace.md,
                            vertical: NiraSpace.md,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  variant == ProductionVariant.grade
                                      ? 'Grade'
                                      : 'Rendemen',
                                  style: niraText(
                                    NiraType.caption,
                                    color: variant == widget.analytics.variant
                                        ? Colors.white
                                        : niraGreen,
                                    weight: variant == widget.analytics.variant
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (variant == widget.analytics.variant)
                                const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                            ],
                          ),
                        ),
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
                if (widget.onFilter != null) ...[
                  const SizedBox(width: NiraSpace.sm),
                  ReportDateButton(onPressed: widget.onFilter!),
                ],
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
                    ]
                  : [_legend('Gula final (kg)', _barColor)],
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
                  final plot = Rect.fromLTRB(32, 16, width - 8, 154);
                  final detailWidth = selected < 0
                      ? 0.0
                      : math.min(
                          width,
                          _detailWidth(context, days[selected], grade),
                        );
                  void select(Offset position) {
                    if (!plot.contains(position)) return;
                    final index =
                        ((position.dx - plot.left) / plot.width * days.length)
                            .floor()
                            .clamp(0, days.length - 1);
                    if (_selectedDay != days[index].day) {
                      setState(() => _selectedDay = days[index].day);
                    }
                  }

                  return Semantics(
                    label: grade
                        ? 'Grafik batang grade A, B, C dalam kilogram.'
                        : 'Grafik batang gula dalam kilogram. Ketuk untuk detail gula dan rendemen.',
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
                          height: 180,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ChartGrowth(
                                  replayKey: (
                                    widget.analytics.variant,
                                    widget.analytics.dateFilter,
                                  ),
                                  builder: (context, progress) => CustomPaint(
                                    painter: _ProductionPainter(
                                      days: days,
                                      grade: grade,
                                      selected: selected,
                                      plot: plot,
                                      textDirection: Directionality.of(context),
                                      progress: progress,
                                    ),
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
                                              detailWidth / 2)
                                          .clamp(
                                            0.0,
                                            math.max(0.0, width - detailWidth),
                                          ),
                                  top: 0,
                                  width: detailWidth,
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
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: NiraSpace.xs),
      Text(label, style: niraText(NiraType.caption, color: niraLeaf)),
    ],
  );

  List<String> _detailLines(_ChartDay day, bool grade) => [
    '${day.day} Oktober 2026',
    'Gula final: ${day.kg.toInt()} kg',
    grade
        ? 'A: ${day.a.toInt()} · B: ${day.b.toInt()} · C: ${day.c.toInt()} kg'
        : 'Rendemen: ${day.rendemen.toStringAsFixed(1).replaceAll('.', ',')}%',
  ];

  TextStyle _detailStyle(int index) => niraText(
    NiraType.caption,
    color: index == 2 ? niraYellow : Colors.white,
    height: 1.3,
    weight: index == 0 ? FontWeight.w600 : FontWeight.w400,
  );

  double _detailWidth(BuildContext context, _ChartDay day, bool grade) {
    final lines = _detailLines(day, grade);
    var widest = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final text = TextPainter(
        text: TextSpan(text: lines[i], style: _detailStyle(i)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      widest = math.max(widest, text.width);
      text.dispose();
    }
    return widest.ceilToDouble() + 20;
  }

  Widget _detail(_ChartDay day, bool grade) => Container(
    key: const ValueKey('production-chart-detail'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          Text(_detailLines(day, grade)[i], style: _detailStyle(i)),
        ],
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
    required this.progress,
  });
  final List<_ChartDay> days;
  final bool grade;
  final int selected;
  final Rect plot;
  final TextDirection textDirection;
  final double progress;

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
    }
    final slot = plot.width / days.length;
    final barWidth = math.min(19.0, slot * .48);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final x = plot.left + slot * (i + .5);
      if (grade) {
        var bottom = plot.bottom;
        for (final (value, color) in [
          (day.c, _gradeC),
          (day.b, _gradeB),
          (day.a, niraGreen),
        ]) {
          final h = value / 100 * plot.height * progress;
          canvas.drawRect(
            Rect.fromLTWH(x - barWidth / 2, bottom - h, barWidth, h),
            Paint()
              ..color = i == selected
                  ? Color.lerp(color, Colors.white, .12)!
                  : color,
          );
          bottom -= h;
        }
      } else {
        final h = day.kg / 100 * plot.height * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, plot.bottom - h, barWidth, h),
            const Radius.circular(4),
          ),
          Paint()..color = i == selected ? niraGreenHover : _barColor,
        );
      }
      _text(canvas, '${day.day}', Offset(x, plot.bottom + 16));
    }
  }

  @override
  bool shouldRepaint(covariant _ProductionPainter old) =>
      old.progress != progress ||
      old.grade != grade ||
      old.selected != selected ||
      old.plot != plot ||
      !listEquals(old.days, days);
}
