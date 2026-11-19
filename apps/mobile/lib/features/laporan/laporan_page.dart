import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_date_filter.dart';
import 'demo_analytics.dart';
import '../kloter/demo_lot_fixture.dart';
import 'margin_chart.dart';
import 'production_chart.dart';
import 'report_detail_page.dart';
import 'report_paginated_list.dart';
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
    plain: true,
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
    plain: true,
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
    plain: true,
    columns: const ['Pemasok', 'Margin'],
    rows: widget.analytics.visibleRows,
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
                      child: Text(
                        row.value,
                        textAlign: TextAlign.center,
                        style: niraText(NiraType.body),
                      ),
                    ),
                    if (columns.length > 2)
                      Expanded(
                        flex: 3,
                        child: Text(
                          row.secondary,
                          textAlign: TextAlign.center,
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
    resetToken: (title, widget.analytics.dateFilter, widget.analytics.query),
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
