import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_date_filter.dart';
import 'demo_analytics.dart';
import '../kloter/demo_lot_fixture.dart';
import 'margin_chart.dart';
import 'production_chart.dart';
import 'report_detail_page.dart';
import 'report_table.dart';
import '../kloter/demo_production.dart';
import 'production_recap.dart';
import 'production_recap_section.dart';
import 'report_date_button.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({
    required this.analytics,
    required this.onOpenDetail,
    this.approvedLots,
    this.statusMessage,
    super.key,
  });

  final DemoAnalytics analytics;
  final ValueChanged<ReportDetailKind> onOpenDetail;
  final List<DemoKloter>? approvedLots;
  final Widget? statusMessage;

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  Future<void> _dateFilter() async {
    FocusScope.of(context).unfocus();
    final result = await showKloterDateFilter(
      context,
      widget.analytics.dateFilter,
      today: widget.approvedLots == null ? null : DateTime.now(),
    );
    if (!mounted || result == null) return;
    widget.analytics.setDateFilter(result.selection);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.analytics,
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
          child: widget.approvedLots != null
              ? ListView(
                  key: const PageStorageKey('laporan-connected-scroll'),
                  padding: EdgeInsets.fromLTRB(
                    niraPageInset(context),
                    NiraSpace.md,
                    niraPageInset(context),
                    NiraSpace.lg,
                  ),
                  children: [_connectedReport()],
                )
              : widget.analytics.tab == ReportTab.production
              ? _production()
              : _margin(),
        ),
      ],
    ),
  );

  Widget _connectedReport() {
    if (widget.analytics.tab == ReportTab.margin) {
      return const NiraSummaryCard('Margin produksi', 'Belum tersedia');
    }
    final lots = widget.approvedLots!
        .where((lot) => widget.analytics.dateFilter?.contains(lot.date) ?? true)
        .toList();
    final weights = lots.map((lot) => lot.netWeightKg).nonNulls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NiraSummaryPair(
          first: const NiraSummaryCard('Gula final', 'Belum tersedia'),
          second: NiraSummaryCard(
            'Tebu diterima',
            formatQuantity(
              weights.isEmpty ? null : weights.reduce((a, b) => a + b),
              'kg',
            ),
            boxes: true,
          ),
        ),
        const SizedBox(height: NiraSpace.md),
        Align(
          alignment: Alignment.centerRight,
          child: ReportDateButton(onPressed: _dateFilter),
        ),
        const SizedBox(height: NiraSpace.md),
        widget.statusMessage ??
            ProductionRecapSection(
              recap: ProductionRecap.fromApprovedLots(lots),
            ),
      ],
    );
  }

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
          '${demoNumber(widget.analytics.sugarTotal)}Kg',
        ),
        second: NiraSummaryCard(
          'Tebu diterima',
          '${demoNumber(widget.analytics.caneTotal)}Kg',
          boxes: true,
        ),
      ),
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
        demoMoney(widget.analytics.marginTotal),
        cane: true,
        compactValue: true,
      ),
      const SizedBox(height: NiraSpace.sm),
      NiraSummaryPair(
        first: NiraSummaryCard(
          'Nilai produksi',
          demoMoney(widget.analytics.valueTotal),
          compactValue: true,
        ),
        second: NiraSummaryCard(
          'Total biaya',
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
      ? MarginChart(rows: widget.analytics.visibleRows, onFilter: _dateFilter)
      : ProductionChart(analytics: widget.analytics, onFilter: _dateFilter);

  Widget _rendemenTable(Widget header) => _tableSection(
    title: 'Rendemen',
    scrollHeader: header,
    columns: const ['Pemasok', 'Gula final', 'Rendemen'],
    rows: widget.analytics.visibleRows,
    onTap: (row) {
      widget.analytics.selectedRow = row;
      widget.onOpenDetail(ReportDetailKind.rendemen);
    },
  );

  Widget _gradeTable(Widget header) => _tableSection(
    title: 'Komposisi Grade',
    scrollHeader: header,
    columns: const ['Grade', 'Berat', 'Porsi'],
    rows: [
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
    columns: const ['Pemasok', 'Margin'],
    rows: widget.analytics.visibleRows,
    onTap: (row) {
      widget.analytics.selectedRow = row;
      widget.onOpenDetail(ReportDetailKind.margin);
    },
  );

  Widget _tableSection({
    required String title,
    required Widget scrollHeader,
    required List<String> columns,
    required List<AnalyticsRow> rows,
    required ValueChanged<AnalyticsRow> onTap,
  }) => ReportTable<AnalyticsRow>(
    title: title,
    columns: columns,
    rows: rows,
    scrollHeader: scrollHeader,
    resetToken: (title, widget.analytics.dateFilter, widget.analytics.query),
    leading: (row) => Text(row.supplier, style: niraText(NiraType.body)),
    value: (row) => row.value,
    secondary: columns.length > 2 ? (row) => row.secondary : null,
    onTap: onTap,
  );
}
