import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/kloter_cane_overlay.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'report_paginated_list.dart';

class ReportDetailLayout extends StatelessWidget {
  const ReportDetailLayout({
    required this.title,
    required this.onNavigate,
    required this.children,
    this.tab = NiraTab.laporan,
    super.key,
  });
  final String title;
  final ValueChanged<NiraTab> onNavigate;
  final List<Widget> children;
  final NiraTab tab;

  @override
  Widget build(BuildContext context) => NiraScaffold(
    tab: tab,
    onNavigate: onNavigate,
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        niraPageInset(context),
        NiraSpace.sm,
        niraPageInset(context),
        NiraSpace.lg,
      ),
      children: [
        DetailTitle(title, inset: 0),
        const SizedBox(height: NiraSpace.xs),
        ...children,
      ],
    ),
  );
}

class ReportEntityCard extends StatelessWidget {
  const ReportEntityCard({
    required this.code,
    required this.supplier,
    required this.date,
    super.key,
  });
  final String code, supplier, date;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: niraSummaryGradient,
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Stack(
      children: [
        const KloterCaneOverlay(),
        Padding(
          padding: const EdgeInsets.all(NiraSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                style: niraText(
                  NiraType.title,
                  color: niraYellow,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                supplier,
                style: niraText(NiraType.body, color: Colors.white),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                date,
                style: niraText(NiraType.caption, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ReportMoneyTable extends StatelessWidget {
  const ReportMoneyTable({required this.rows, required this.total, super.key});
  final List<(String, String)> rows;
  final (String, String) total;

  Widget _row((String, String) row, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            row.$1,
            style: niraText(
              NiraType.body,
              weight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: NiraSpace.sm),
        Flexible(
          child: Text(
            row.$2,
            textAlign: TextAlign.end,
            style: niraText(
              NiraType.body,
              weight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(NiraSpace.sm),
      child: Column(
        children: [
          _row(('Komponen', 'Nilai'), bold: true),
          for (final row in rows) _row(row),
          const Divider(height: 12, thickness: 1, color: niraLine),
          _row(total, bold: true),
        ],
      ),
    ),
  );
}

class ReportContribution {
  const ReportContribution(
    this.label,
    this.weight,
    this.value, {
    this.note,
    this.onOpen,
  });
  final String label, weight, value;
  final String? note;
  final VoidCallback? onOpen;
}

class ReportContributionTable extends StatelessWidget {
  const ReportContributionTable({
    required this.columns,
    required this.rows,
    this.total,
    super.key,
  });
  final List<String> columns;
  final List<ReportContribution> rows;
  final ReportContribution? total;

  Widget _row(ReportContribution row, {bool header = false}) => InkWell(
    onTap: row.onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: NiraSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (index, text) in [
                row.label,
                row.weight,
                row.value,
              ].indexed)
                Expanded(
                  flex: index == 0 ? 4 : 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: NiraSpace.xs),
                    child: Text(
                      text,
                      textAlign: index == 2 ? TextAlign.end : TextAlign.start,
                      style: niraText(
                        NiraType.body,
                        weight: header ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              if (row.onOpen != null) const Icon(Icons.chevron_right, size: 18),
            ],
          ),
          if (row.note case final note?) ...[
            const SizedBox(height: NiraSpace.xs),
            Text(note, style: niraText(NiraType.caption, color: niraLeaf)),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(NiraSpace.sm),
      child: Column(
        children: [
          _row(
            ReportContribution(columns[0], columns[1], columns[2]),
            header: true,
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(NiraSpace.md),
              child: Text('Data tidak ditemukan'),
            ),
          ReportPaginatedList<ReportContribution>(
            items: rows,
            resetToken: rows,
            builder: (items) =>
                Column(children: [for (final item in items) _row(item)]),
          ),
          if (total case final row?) ...[
            const Divider(height: 10),
            _row(row, header: true),
          ],
        ],
      ),
    ),
  );
}
