import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/chart_growth.dart';
import '../kloter/demo_lot_fixture.dart';
import '../kloter/demo_production.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';
import 'demo_analytics.dart';
import 'report_date_button.dart';

const _barColor = niraGreen;
const _gradeB = Color(0xFFD3A734);
const _gradeC = Color(0xFFDCE6DE);

class _ChartDay {
  const _ChartDay(this.date, this.kg, this.rendemen, this.a, this.b, this.c);
  final DateTime date;
  final double kg;
  final double rendemen;
  final double a;
  final double b;
  final double c;
}

class ProductionChart extends StatefulWidget {
  const ProductionChart({
    required this.analytics,
    this.reports,
    this.onFilter,
    super.key,
  });
  final DemoAnalytics analytics;
  final ConnectedReports? reports;
  final VoidCallback? onFilter;

  @override
  State<ProductionChart> createState() => _ProductionChartState();
}

class _ProductionChartState extends State<ProductionChart> {
  DateTime? _selectedDay;

  _ChartDay _chartDay(DateTime date) {
    final lots = widget.analytics.visibleLots.where(
      (lot) => lot.day == date.day,
    );
    final sugar = lots.fold(0, (sum, lot) => sum + lot.sugarKg);
    final cane = lots.fold(0, (sum, lot) => sum + lot.caneKg);
    double grade(String code) {
      var total = 0;
      for (final lot in lots) {
        for (final (i, weight) in lot.batchWeights.indexed) {
          if (['A', 'B', 'C'][i % 3] == code) total += weight;
        }
      }
      return total.toDouble();
    }

    return _ChartDay(
      date,
      sugar.toDouble(),
      cane == 0 ? 0 : sugar / cane * 100,
      grade('A'),
      grade('B'),
      grade('C'),
    );
  }

  List<_ChartDay> _officialDays(ConnectedReports reports) {
    final byDate = <DateTime, List<Json>>{};
    for (final lot in reports.lots) {
      if (lot['calculation'] == null) continue;
      final local = DateTime.parse(lot['receivedAt'] as String).toLocal();
      final date = DateTime(local.year, local.month, local.day);
      (byDate[date] ??= []).add(lot);
    }
    return [
      for (final date in byDate.keys.toList()..sort())
        _officialDay(date, byDate[date]!),
    ];
  }

  _ChartDay _officialDay(DateTime date, List<Json> lots) {
    double sugar = 0, cane = 0;
    final grades = <String, double>{};
    double quantity(Object? value) => double.tryParse('$value') ?? 0;
    for (final lot in lots) {
      cane += quantity(lot['caneNetKg']);
      sugar += quantity((lot['calculation'] as Json)['finalSugarKg']);
      for (final batch in (lot['batches'] as List).cast<Json>()) {
        for (final grade in (batch['grades'] as List).cast<Json>()) {
          final code = grade['code'] as String;
          grades.update(
            code,
            (total) => total + quantity(grade['weightKg']),
            ifAbsent: () => quantity(grade['weightKg']),
          );
        }
      }
    }
    return _ChartDay(
      date,
      sugar,
      cane == 0 ? 0 : sugar / cane * 100,
      grades['A'] ?? 0,
      grades['B'] ?? 0,
      grades['C'] ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final grade = widget.analytics.variant == ProductionVariant.grade;
    final dates =
        widget.analytics.visibleLots.map((lot) => lot.day).toSet().toList()
          ..sort();
    final reports = widget.reports;
    final days = reports == null
        ? [for (final day in dates) _chartDay(DateTime(2026, 10, day))]
        : _officialDays(reports);
    final selected = days.indexWhere((day) => day.date == _selectedDay);
    return NiraOutline(
      Padding(
        padding: const EdgeInsets.all(NiraSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'Gula final per hari (Kg)',
                  style: niraText(NiraType.body, weight: FontWeight.w700),
                );
                final controls = Wrap(
                  spacing: NiraSpace.sm,
                  runSpacing: NiraSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
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
                                        color:
                                            variant == widget.analytics.variant
                                            ? Colors.white
                                            : niraGreen,
                                        weight:
                                            variant == widget.analytics.variant
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
                            Flexible(
                              child: Text(
                                grade ? 'Grade' : 'Rendemen',
                                style: niraText(
                                  NiraType.caption,
                                  weight: FontWeight.w600,
                                ),
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
                    if (widget.onFilter != null)
                      ReportDateButton(onPressed: widget.onFilter!),
                  ],
                );
                final textSize = MediaQuery.textScalerOf(
                  context,
                ).scale(NiraType.body);
                if (constraints.maxWidth < 260 || textSize > 16) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: NiraSpace.sm,
                    children: [title, controls],
                  );
                }
                return Row(
                  spacing: NiraSpace.sm,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: title,
                      ),
                    ),
                    controls,
                  ],
                );
              },
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
                    if (_selectedDay != days[index].date) {
                      setState(() => _selectedDay = days[index].date);
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
                                    reports?.filter ??
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
      Flexible(
        child: Text(label, style: niraText(NiraType.caption, color: niraLeaf)),
      ),
    ],
  );

  List<String> _detailLines(_ChartDay day, bool grade) => [
    formatDate(day.date),
    'Gula final: ${demoNumber(day.kg, decimals: day.kg % 1 == 0 ? 0 : 3)} kg',
    grade
        ? 'A: ${_chartAmount(day.a)} · B: ${_chartAmount(day.b)} · C: ${_chartAmount(day.c)} kg'
        : 'Rendemen: ${day.rendemen.toStringAsFixed(1).replaceAll('.', ',')}%',
  ];

  String _chartAmount(double value) =>
      demoNumber(value, decimals: value % 1 == 0 ? 0 : 3);

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
    final maximum = math.max(
      100.0,
      (days.fold<double>(0, (highest, day) => math.max(highest, day.kg)) / 100)
              .ceil() *
          100.0,
    );
    final grid = Paint()
      ..color = niraLine
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final y = plot.bottom - tick * plot.height / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(
        canvas,
        '${(tick * maximum / 4).round()}',
        Offset(plot.left - 18, y),
      );
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
          final h = value / maximum * plot.height * progress;
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
        final h = day.kg / maximum * plot.height * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, plot.bottom - h, barWidth, h),
            const Radius.circular(4),
          ),
          Paint()..color = i == selected ? niraGreenHover : _barColor,
        );
      }
      final multiMonth =
          days.first.date.month != days.last.date.month ||
          days.first.date.year != days.last.date.year;
      final label = multiMonth
          ? '${day.date.day}/${day.date.month}'
          : '${day.date.day}';
      _text(canvas, label, Offset(x, plot.bottom + 16));
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
