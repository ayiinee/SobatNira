import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/adaptive_value.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_date_filter.dart';
import 'connected_report_controls.dart'
    show ConnectedReportStatus, filterConnectedReport;
import 'connected_reports.dart';
import 'demo_analytics.dart';
import '../kloter/demo_lot_fixture.dart';
import 'margin_chart.dart';
import 'production_chart.dart';
import 'report_detail_page.dart';
import 'report_paginated_list.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({
    required this.analytics,
    required this.onOpenDetail,
    this.reports,
    super.key,
  });

  final DemoAnalytics analytics;
  final ValueChanged<ReportDetailKind> onOpenDetail;
  final ConnectedReports? reports;

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  ConnectedReports? get _reports => widget.reports;
  List<AnalyticsRow> get _rows =>
      _reports?.rows(widget.analytics.tab) ?? widget.analytics.visibleRows;

  Future<void> _dateFilter() async {
    FocusScope.of(context).unfocus();
    if (_reports case final reports?) {
      return filterConnectedReport(context, reports);
    }
    final result = await showKloterDateFilter(
      context,
      widget.analytics.dateFilter,
    );
    if (!mounted || result == null) return;
    widget.analytics.setDateFilter(result.selection);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.analytics, _reports]),
    builder: (context, _) => Column(
      children: [
        NiraTabs(
          labels: const ['Produksi', 'Margin'],
          selected: widget.analytics.tab.index,
          height: 43,
          inset: 20,
          onSelected: (index) =>
              widget.analytics.setTab(ReportTab.values[index]),
        ),
        Expanded(
          child: widget.analytics.tab == ReportTab.production
              ? _production()
              : _margin(),
        ),
      ],
    ),
  );

  Widget _production() {
    final header = _productionHeader();
    return widget.analytics.variant == ProductionVariant.grade
        ? _gradeTable(header)
        : _rendemenTable(header);
  }

  Widget _productionHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NiraSummaryPair(
        first: NiraSummaryCard(
          'Gula final',
          _reports?.amount('finalSugarKg', unit: ' kg') ??
              '${demoNumber(widget.analytics.sugarTotal)}Kg',
        ),
        second: NiraSummaryCard(
          'Tebu diterima (kg)',
          _reports?.amount('caneNetKg') ??
              demoNumber(widget.analytics.caneTotal),
          boxes: true,
        ),
      ),
      if (_reports case final reports?) ConnectedReportStatus(reports: reports),
      const SizedBox(height: NiraSpace.md),
      _chartCard(),
      const SizedBox(height: NiraSpace.md),
    ],
  );

  Widget _marginHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NiraSummaryCard(
        'Margin Produksi',
        _reports?.amount('productionMarginRupiah', money: true) ??
            demoMoney(widget.analytics.marginTotal),
        cane: true,
        compactValue: true,
      ),
      if (_reports case final reports?) ...[
        ConnectedReportStatus(reports: reports),
        if (reports.provisional)
          Text(
            'Margin sementara untuk kloter yang masih terbuka.',
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
      ],
      const SizedBox(height: NiraSpace.sm),
      NiraSummaryPair(
        first: NiraSummaryCard(
          'Nilai produksi',
          _reports?.amount('productionValueRupiah', money: true) ??
              demoMoney(widget.analytics.valueTotal),
          compactValue: true,
        ),
        second: NiraSummaryCard(
          'Total biaya',
          _reports?.amount('totalCostRupiah', money: true) ??
              demoMoney(widget.analytics.costTotal),
          boxes: true,
          compactValue: true,
        ),
      ),
      const SizedBox(height: NiraSpace.md),
      _chartCard(margin: true),
      const SizedBox(height: NiraSpace.md),
    ],
  );

  Widget _chartCard({bool margin = false}) => margin
      ? MarginChart(
          rows: _rows.where((row) => row.value != '—').toList(),
          onFilter: _dateFilter,
        )
      : ProductionChart(
          analytics: widget.analytics,
          reports: _reports,
          onFilter: _dateFilter,
        );

  Widget _rendemenTable(Widget header) => _tableSection(
    title: 'Rendemen',
    scrollHeader: header,
    plain: true,
    columns: const ['Pemasok', 'Gula final', 'Rendemen'],
    rows: _rows,
    onTap: (row) {
      widget.analytics.selectedRow = row;
      widget.onOpenDetail(ReportDetailKind.rendemen);
    },
  );

  Widget _gradeTable(Widget header) => _tableSection(
    title: 'Komposisi Grade',
    scrollHeader: header,
    plain: true,
    columns: const ['Grade', 'Berat', 'Porsi'],
    rows:
        _reports?.gradeRows ??
        [
          for (final grade in ['A', 'B', 'C'])
            AnalyticsRow(
              'Grade $grade',
              '',
              '${widget.analytics.gradeWeight(grade)}Kg',
              widget.analytics.sugarTotal == 0
                  ? '0,0%'
                  : '${demoNumber(widget.analytics.gradeWeight(grade) / widget.analytics.sugarTotal * 100, decimals: 1)}%',
            ),
        ],
    onTap: (row) {
      widget.analytics.selectedRow = row;
      widget.onOpenDetail(ReportDetailKind.grade);
    },
  );

  Widget _margin() => _tableSection(
    title: 'Detail margin kloter',
    scrollHeader: _marginHeader(),
    plain: true,
    columns: const ['Pemasok', 'Margin'],
    rows: _rows,
    onTap: (row) {
      widget.analytics.selectedRow = row;
      widget.onOpenDetail(ReportDetailKind.margin);
    },
  );

  Widget _plainTable(
    String title,
    List<String> columns,
    List<AnalyticsRow> rows,
    ValueChanged<AnalyticsRow> onTap,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: niraText(NiraType.section, weight: FontWeight.w700)),
      const SizedBox(height: NiraSpace.sm),
      Row(
        children: [
          for (var index = 0; index < columns.length; index++)
            Expanded(
              flex: index == 0 ? 4 : 3,
              child: Text(
                columns[index],
                textAlign: index == 0 ? TextAlign.start : TextAlign.center,
                style: niraText(
                  NiraType.caption,
                  color: const Color(0xFF858B87),
                  weight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 20),
        ],
      ),
      const SizedBox(height: NiraSpace.xs),
      const Divider(height: 1, thickness: 1, color: niraLine),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NiraSpace.lg),
          child: Text(
            'Data tidak ditemukan',
            textAlign: TextAlign.center,
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
        )
      else
        for (final row in rows) ...[
          InkWell(
            onTap: () => onTap(row),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(row.supplier, style: niraText(NiraType.body)),
                    ),
                    Expanded(
                      flex: 3,
                      child: NiraValue(
                        row.value,
                        label: row.supplier,
                        alignment: Alignment.center,
                        style: niraText(NiraType.body),
                      ),
                    ),
                    if (columns.length > 2)
                      Expanded(
                        flex: 3,
                        child: NiraValue(
                          row.secondary,
                          alignment: Alignment.center,
                          style: niraText(NiraType.body),
                        ),
                      ),
                    const Icon(Icons.chevron_right, color: niraGreen, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: niraLine),
        ],
    ],
  );

  Widget _tableSection({
    required String title,
    required Widget scrollHeader,
    required List<String> columns,
    required List<AnalyticsRow> rows,
    required ValueChanged<AnalyticsRow> onTap,
    bool plain = false,
  }) => ReportPaginatedList<AnalyticsRow>(
    items: rows,
    scrollHeader: scrollHeader,
    resetToken: (
      title,
      _reports?.filter ?? widget.analytics.dateFilter,
      widget.analytics.query,
    ),
    builder: (visibleRows) => plain
        ? _plainTable(title, columns, visibleRows, onTap)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: niraText(NiraType.section, weight: FontWeight.w600),
              ),
              const SizedBox(height: NiraSpace.xs),
              NiraOutline(
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NiraSpace.sm,
                        NiraSpace.sm,
                        NiraSpace.sm,
                        NiraSpace.xs,
                      ),
                      child: Row(
                        children: [
                          for (final column in columns)
                            Expanded(
                              child: Text(
                                column,
                                style: niraText(
                                  NiraType.caption,
                                  color: niraLeaf,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (visibleRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(NiraSpace.lg),
                        child: Text(
                          'Data tidak ditemukan',
                          textAlign: TextAlign.center,
                          style: niraText(NiraType.caption, color: niraLeaf),
                        ),
                      )
                    else
                      for (final row in visibleRows)
                        InkWell(
                          onTap: () => onTap(row),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              NiraSpace.sm,
                              NiraSpace.sm,
                              NiraSpace.sm,
                              NiraSpace.sm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.supplier,
                                    style: niraText(NiraType.body),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    row.value,
                                    style: niraText(NiraType.body),
                                  ),
                                ),
                                if (columns.length > 2)
                                  Expanded(
                                    child: Text(
                                      row.secondary,
                                      style: niraText(NiraType.body),
                                    ),
                                  ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 15,
                                  color: niraGreen,
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
  );
}
