import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
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
          padding: const EdgeInsets.fromLTRB(28, 13, 21, 3),
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
          padding: const EdgeInsets.fromLTRB(niraInset, 13, niraInset, 88),
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
          style: niraText(12.5),
          decoration: InputDecoration(
            hintText: 'Telusuri Kloter berdasarkan ID',
            hintStyle: niraText(12),
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 11),
              child: NiraIcon('search', 21, color: niraGreen),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 42),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            onTap: _dateFilter,
            borderRadius: BorderRadius.circular(7),
            child: const SizedBox.square(
              dimension: 45,
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
    borderRadius: BorderRadius.circular(7),
    borderSide: BorderSide(color: niraGreen, width: width),
  );

  Widget _production() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        spacing: 8,
        children: [
          Expanded(child: _metric('Gula final', '360Kg')),
          Expanded(child: _metric('Tebu diterima', '5.567Kg')),
        ],
      ),
      const SizedBox(height: 10),
      _chartCard(),
      const SizedBox(height: 13),
      if (widget.analytics.variant == ProductionVariant.grade)
        _gradeTable()
      else
        _rendemenTable(),
    ],
  );

  Widget _margin() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _metric('Margin Produksi', 'Rp1.580.000', wide: true),
      const SizedBox(height: 9),
      Row(
        spacing: 8,
        children: [
          Expanded(child: _metric('Nilai produksi', '360Kg')),
          Expanded(child: _metric('Total biaya', '5.567Kg')),
        ],
      ),
      const SizedBox(height: 10),
      _chartCard(margin: true),
      const SizedBox(height: 13),
      _marginTable(),
    ],
  );

  Widget _metric(String label, String value, {bool wide = false}) => Container(
    constraints: const BoxConstraints(minHeight: 62),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(7),
      boxShadow: const [niraShadow],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: niraText(wide ? 11 : 10.5, color: Colors.white)),
        const SizedBox(height: 2),
        Text(
          value,
          style: niraText(
            wide ? 23 : 19,
            color: niraYellow,
            weight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _chartCard({bool margin = false}) => NiraOutline(
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  margin
                      ? 'Margin per kloter (1000)'
                      : 'Gula final per hari (Kg)',
                  style: niraText(11.5, weight: FontWeight.w700),
                ),
              ),
              if (!margin) ...[
                _modeChip('Rendemen', ProductionVariant.rendemen),
                const SizedBox(width: 3),
                _modeChip('Grade', ProductionVariant.grade),
              ],
            ],
          ),
          const SizedBox(height: 6),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: widget.analytics.variant == value
              ? const Color(0xFFE8F0E7)
              : const Color(0xFFF2F2EF),
          border: Border.all(
            color: widget.analytics.variant == value ? niraLeaf : niraMuted,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: niraText(8.5, weight: FontWeight.w600)),
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
      Text(title, style: niraText(14.5, weight: FontWeight.w700)),
      const SizedBox(height: 5),
      NiraOutline(
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 7, 5),
              child: Row(
                children: [
                  for (final column in columns)
                    Expanded(
                      child: Text(
                        column,
                        style: niraText(
                          10,
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
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Data tidak ditemukan',
                  textAlign: TextAlign.center,
                  style: niraText(11.5, color: niraLeaf),
                ),
              )
            else
              for (final row in rows.take(7))
                InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 6, 7, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(row.supplier, style: niraText(10.5)),
                        ),
                        Expanded(child: Text(row.value, style: niraText(10.5))),
                        if (columns.length > 2)
                          Expanded(
                            child: Text(row.secondary, style: niraText(10.5)),
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
