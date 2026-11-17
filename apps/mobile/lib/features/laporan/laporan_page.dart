import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_date_filter.dart';
import 'demo_analytics.dart';
import 'report_detail_page.dart';

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
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
    builder: (context, _) => CustomScrollView(
      key: const PageStorageKey('laporan-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            niraInset,
            NiraSpace.lg,
            niraInset,
            NiraSpace.sm,
          ),
          sliver: SliverToBoxAdapter(child: _searchRow()),
        ),
        SliverToBoxAdapter(
          child: NiraTabs(
            labels: const ['Produksi', 'Margin'],
            selected: widget.analytics.tab.index,
            height: 43,
            inset: 20,
            onSelected: (index) =>
                widget.analytics.setTab(ReportTab.values[index]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(niraInset, 13, niraInset, NiraSpace.lg),
          sliver: SliverList.list(
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

  Widget _searchRow() => Row(
    spacing: 8,
    children: [
      Expanded(
        child: TextField(
          controller: _search,
          onChanged: widget.analytics.setQuery,
          style: niraText(NiraType.body),
          decoration: InputDecoration(
            hintText: 'Telusuri Kloter berdasarkan ID',
            hintStyle: niraText(NiraType.body, color: niraLeaf),
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: NiraSpace.md),
              child: NiraIcon('search', 21, color: niraGreen),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 42),
            contentPadding: const EdgeInsets.symmetric(vertical: NiraSpace.lg),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            enabledBorder: _border(),
            focusedBorder: _border(width: 2),
          ),
        ),
      ),
      Semantics(
        label: 'Filter tanggal laporan',
        button: true,
        child: Material(
          color: niraGreen,
          borderRadius: BorderRadius.circular(niraRadius),
          child: InkWell(
            onTap: _dateFilter,
            borderRadius: BorderRadius.circular(niraRadius),
            child: const SizedBox.square(
              dimension: 48,
              child: Center(
                child: NiraIcon('calendar', 26, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  OutlineInputBorder _border({double width = 1.3}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(niraRadius),
    borderSide: BorderSide(color: niraGreen, width: width),
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

  Widget _chartCard({bool margin = false}) => NiraOutline(
    Padding(
      padding: const EdgeInsets.fromLTRB(
        NiraSpace.sm,
        NiraSpace.sm,
        NiraSpace.sm,
        NiraSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            margin ? 'Margin per kloter (1000)' : 'Gula final per hari (Kg)',
            style: niraText(NiraType.body, weight: FontWeight.w600),
          ),
          if (!margin) ...[
            const SizedBox(height: NiraSpace.sm),
            Wrap(
              spacing: NiraSpace.sm,
              runSpacing: NiraSpace.sm,
              children: [
                _modeChip('Rendemen', ProductionVariant.rendemen),
                _modeChip('Grade', ProductionVariant.grade),
              ],
            ),
          ],
          const SizedBox(height: NiraSpace.sm),
          SizedBox(
            height: 134,
            child: CustomPaint(
              painter: _ReportChartPainter(
                margin: margin,
                bars:
                    margin ||
                    widget.analytics.variant == ProductionVariant.grade,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _modeChip(String label, ProductionVariant value) => Semantics(
    label: label,
    button: true,
    selected: widget.analytics.variant == value,
    child: InkWell(
      onTap: () => widget.analytics.setVariant(value),
      borderRadius: BorderRadius.circular(niraRadius),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: NiraSpace.sm,
          vertical: NiraSpace.xs,
        ),
        decoration: BoxDecoration(
          color: widget.analytics.variant == value
              ? const Color(0xFFE8F0E7)
              : const Color(0xFFF2F2EF),
          border: Border.all(
            color: widget.analytics.variant == value ? niraLeaf : niraMuted,
          ),
          borderRadius: BorderRadius.circular(niraRadius),
        ),
        child: Text(
          label,
          style: niraText(NiraType.caption, weight: FontWeight.w600),
        ),
      ),
    ),
  );

  Widget _rendemenTable() => _tableSection(
    title: 'Rendemen',
    columns: const ['Pemasok', 'Gula final', 'Rendemen'],
    rows: widget.analytics.visibleRows,
    onTap: () => widget.onOpenDetail(ReportDetailKind.rendemen),
  );

  Widget _gradeTable() => _tableSection(
    title: 'Komposisi Grade',
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
    columns: const ['Pemasok', 'Margin'],
    rows: widget.analytics.visibleRows,
    onTap: () => widget.onOpenDetail(ReportDetailKind.margin),
  );

  Widget _tableSection({
    required String title,
    required List<String> columns,
    required List<AnalyticsRow> rows,
    required VoidCallback onTap,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: niraText(NiraType.section, weight: FontWeight.w600)),
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

class _ReportChartPainter extends CustomPainter {
  const _ReportChartPainter({required this.margin, required this.bars});

  final bool margin;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = niraMuted.withValues(alpha: .45)
      ..strokeWidth = 1;
    final plot = Rect.fromLTWH(8, 8, size.width - 16, size.height - 24);
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    if (bars) {
      final bar = Paint()..color = niraGreen;
      final gold = Paint()..color = niraGold;
      for (var i = 0; i < 7; i++) {
        final x = plot.left + 15 + i * 31;
        final h1 = 28.0 + (i % 3) * 15.0;
        final h2 = 20.0 + ((i + 1) % 3) * 18.0;
        canvas.drawRect(Rect.fromLTWH(x, plot.bottom - h1, 10.0, h1), bar);
        canvas.drawRect(
          Rect.fromLTWH(x + 11.0, plot.bottom - h2, 10.0, h2),
          gold,
        );
      }
      return;
    }
    final line = Paint()
      ..color = niraLeaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final points = <Offset>[];
    for (var i = 0; i < 7; i++) {
      points.add(
        Offset(plot.left + 10 + i * 32, plot.bottom - 25 - (i % 4) * 22),
      );
    }
    canvas.drawPath(Path()..addPolygon(points, false), line);
    final dot = Paint()..color = niraGreen;
    for (final point in points) {
      canvas.drawCircle(point, 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ReportChartPainter oldDelegate) =>
      oldDelegate.margin != margin || oldDelegate.bars != bars;
}
