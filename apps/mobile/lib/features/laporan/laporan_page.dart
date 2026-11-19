import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_date_filter.dart';
import 'demo_analytics.dart';
import '../kloter/demo_lot_fixture.dart';
import 'margin_chart.dart';
import 'production_chart.dart';
import 'report_detail_page.dart';
import 'report_overview.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({
    required this.analytics,
    required this.onOpenDetail,
    super.key,
  });

  final DemoAnalytics analytics;
  final ValueChanged<ReportDetailKind> onOpenDetail;

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  Future<void> _dateFilter() async {
    FocusScope.of(context).unfocus();
    final result = await showKloterDateFilter(
      context,
      widget.analytics.dateFilter,
    );
    if (!mounted || result == null) return;
    widget.analytics.setDateFilter(result.selection);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.analytics,
    builder: (context, _) {
      final analytics = widget.analytics;
      final margin = analytics.tab == ReportTab.margin;
      final grade = !margin && analytics.variant == ProductionVariant.grade;
      return ReportOverview<AnalyticsRow>(
        tab: analytics.tab,
        onTab: analytics.setTab,
        grade: grade,
        sugar: '${demoNumber(analytics.sugarTotal)}Kg',
        cane: '${demoNumber(analytics.caneTotal)}Kg',
        margin: demoMoney(analytics.marginTotal),
        productionValue: demoMoney(analytics.valueTotal),
        cost: demoMoney(analytics.costTotal),
        options: const ReportDataOptions(synthetic: true),
        chart: margin
            ? MarginChart(rows: analytics.visibleRows, onFilter: _dateFilter)
            : ProductionChart(analytics: analytics, onFilter: _dateFilter),
        rows: grade
            ? [
                for (final code in ['A', 'B', 'C'])
                  AnalyticsRow(
                    'Grade $code',
                    '',
                    '${analytics.gradeWeight(code)}Kg',
                    analytics.sugarTotal == 0
                        ? '0,0%'
                        : '${demoNumber(analytics.gradeWeight(code) / analytics.sugarTotal * 100, decimals: 1)}%',
                  ),
              ]
            : analytics.visibleRows,
        leading: (row) => Text(row.supplier, style: niraText(NiraType.body)),
        value: (row) => row.value,
        secondary: margin ? null : (row) => row.secondary,
        onOpen: (row) {
          analytics.selectedRow = row;
          widget.onOpenDetail(
            margin
                ? ReportDetailKind.margin
                : grade
                ? ReportDetailKind.grade
                : ReportDetailKind.rendemen,
          );
        },
        resetToken: (
          analytics.tab,
          analytics.variant,
          analytics.dateFilter,
          analytics.query,
        ),
      );
    },
  );
}
