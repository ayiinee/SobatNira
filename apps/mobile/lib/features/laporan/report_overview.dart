import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import 'demo_analytics.dart';
import 'report_table.dart';

class ReportDataOptions extends StatelessWidget {
  const ReportDataOptions({required this.synthetic, this.onChanged, super.key});
  final bool synthetic;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: const Text('Tampilkan data contoh'),
    value: synthetic,
    onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
  );
}

// Both data sources supply display values and actions to the same report page.
class ReportOverview<T> extends StatelessWidget {
  const ReportOverview({
    required this.tab,
    required this.onTab,
    required this.grade,
    required this.sugar,
    required this.cane,
    required this.margin,
    required this.productionValue,
    required this.cost,
    required this.chart,
    required this.rows,
    required this.leading,
    required this.value,
    required this.secondary,
    required this.onOpen,
    required this.resetToken,
    this.options,
    this.status,
    super.key,
  });

  final ReportTab tab;
  final ValueChanged<ReportTab> onTab;
  final bool grade;
  final String sugar, cane, margin, productionValue, cost;
  final Widget chart;
  final Widget? options, status;
  final List<T> rows;
  final Widget Function(T) leading;
  final String Function(T) value;
  final String Function(T)? secondary;
  final ValueChanged<T> onOpen;
  final Object resetToken;

  @override
  Widget build(BuildContext context) {
    final marginTab = tab == ReportTab.margin;
    return Column(
      children: [
        NiraTabs(
          labels: const ['Produksi', 'Margin'],
          selected: tab.index,
          onSelected: (index) => onTab(ReportTab.values[index]),
          height: 43,
          inset: 20,
        ),
        Expanded(
          child: ReportTable<T>(
            title: marginTab
                ? 'Detail margin kloter'
                : grade
                ? 'Komposisi Grade'
                : 'Rendemen',
            columns: marginTab
                ? const ['Pemasok', 'Margin']
                : grade
                ? const ['Grade', 'Berat', 'Porsi']
                : const ['Pemasok', 'Gula final', 'Rendemen'],
            rows: rows,
            resetToken: resetToken,
            leading: leading,
            value: value,
            secondary: secondary,
            onTap: onOpen,
            scrollHeader: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (marginTab) ...[
                  NiraSummaryCard(
                    'Margin Produksi',
                    margin,
                    cane: true,
                    compactValue: true,
                  ),
                  const SizedBox(height: NiraSpace.sm),
                  NiraSummaryPair(
                    first: NiraSummaryCard(
                      'Nilai produksi',
                      productionValue,
                      compactValue: true,
                    ),
                    second: NiraSummaryCard(
                      'Total biaya',
                      cost,
                      boxes: true,
                      compactValue: true,
                    ),
                  ),
                ] else
                  NiraSummaryPair(
                    first: NiraSummaryCard('Gula final', sugar),
                    second: NiraSummaryCard('Tebu diterima', cane, boxes: true),
                  ),
                const SizedBox(height: NiraSpace.md),
                chart,
                ?options,
                ?status,
                const SizedBox(height: NiraSpace.md),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
