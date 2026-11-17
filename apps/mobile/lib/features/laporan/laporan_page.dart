import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_date_filter.dart';
import 'demo_analytics.dart';
import 'report_detail_page.dart';
import 'production_chart.dart';
import 'margin_chart.dart';

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
          child: ListView(
            key: const PageStorageKey('laporan-scroll'),
            padding: const EdgeInsets.fromLTRB(
              niraInset,
              NiraSpace.md,
              niraInset,
              NiraSpace.lg,
            ),
            children: [
              if (widget.analytics.tab == ReportTab.production)
                _production()
              else
                _margin(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _production() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const NiraSummaryPair(
        first: NiraSummaryCard('Gula final', '360Kg'),
        second: NiraSummaryCard('Tebu diterima', '5.567Kg', boxes: true),
      ),
      const SizedBox(height: NiraSpace.md),
      _chartCard(),
      const SizedBox(height: NiraSpace.md),
      if (widget.analytics.variant == ProductionVariant.grade)
        _gradeTable()
      else
        _rendemenTable(),
    ],
  );

  Widget _margin() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const NiraSummaryCard('Margin Produksi', 'Rp1.580.000', cane: true),
      const SizedBox(height: NiraSpace.sm),
      const NiraSummaryPair(
        first: NiraSummaryCard('Nilai produksi', '360Kg'),
        second: NiraSummaryCard('Total biaya', '5.567Kg', boxes: true),
      ),
      const SizedBox(height: NiraSpace.md),
      _chartCard(margin: true),
      const SizedBox(height: NiraSpace.md),
      _marginTable(),
    ],
  );

  Widget _chartCard({bool margin = false}) => margin
      ? MarginChart(rows: widget.analytics.visibleRows, onFilter: _dateFilter)
      : ProductionChart(analytics: widget.analytics, onFilter: _dateFilter);

  Widget _rendemenTable() => _tableSection(
    title: 'Rendemen',
    plain: true,
    columns: const ['Pemasok', 'Gula final', 'Rendemen'],
    rows: widget.analytics.visibleRows,
    onTap: () => widget.onOpenDetail(ReportDetailKind.rendemen),
  );

  Widget _gradeTable() => _tableSection(
    title: 'Komposisi Grade',
    plain: true,
    columns: const ['Grade', 'Berat', 'Porsi'],
    rows: const [
      AnalyticsRow('Grade A', '', '90Kg', '50,0%'),
      AnalyticsRow('Grade B', '', '90Kg', '50,0%'),
      AnalyticsRow('Grade C', '', '90Kg', '50,0%'),
    ],
    onTap: () => widget.onOpenDetail(ReportDetailKind.grade),
  );

  Widget _marginTable() => _tableSection(
    title: 'Detail margin kloter',
    plain: true,
    columns: const ['Pemasok', 'Margin'],
    rows: widget.analytics.visibleRows,
    onTap: () => widget.onOpenDetail(ReportDetailKind.margin),
  );

  Widget _plainTable(
    String title,
    List<String> columns,
    List<AnalyticsRow> rows,
    VoidCallback onTap,
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
            onTap: onTap,
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
    required List<String> columns,
    required List<AnalyticsRow> rows,
    required VoidCallback onTap,
    bool plain = false,
  }) => plain
      ? _plainTable(title, columns, rows, onTap)
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
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(NiraSpace.lg),
                      child: Text(
                        'Data tidak ditemukan',
                        textAlign: TextAlign.center,
                        style: niraText(NiraType.caption, color: niraLeaf),
                      ),
                    )
                  else
                    for (final row in rows.take(7))
                      InkWell(
                        onTap: onTap,
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
        );
}

