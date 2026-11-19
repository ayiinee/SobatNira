import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'report_detail_layout.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'report_paginated_list.dart';
import 'demo_analytics.dart';
import '../kloter/demo_lot_fixture.dart';
import '../kloter/demo_production.dart';

enum ReportDetailKind { rendemen, grade, margin }

class ReportDetailPage extends StatelessWidget {
  const ReportDetailPage({
    required this.kind,
    required this.onNavigate,
    this.row,
    this.analytics,
    super.key,
  });

  final ReportDetailKind kind;
  final AnalyticsRow? row;
  final DemoAnalytics? analytics;
  DemoLotFixture get lot => demoLotFor(
    row?.code.isNotEmpty == true ? row!.code : demoLotFixtures.first.code,
  );
  String get grade => row?.supplier.startsWith('Grade ') == true
      ? row!.supplier.substring(6)
      : 'A';
  int get gradeTotal =>
      analytics?.gradeWeight(grade) ??
      lot.batchWeights.indexed
          .where((entry) => ['A', 'B', 'C'][entry.$1 % 3] == grade)
          .fold(0, (sum, entry) => sum + entry.$2);
  List<(String, String, String)> get contributions {
    if (kind == ReportDetailKind.grade) {
      return [
        for (final source in analytics?.visibleLots ?? [lot])
          if (_gradeKg(source) > 0)
            (
              source.code,
              '${_gradeKg(source)}Kg',
              '${demoNumber(_gradeKg(source) / gradeTotal * 100, decimals: 1)}%',
            ),
      ];
    }
    return [
      for (final (index, weight) in lot.batchWeights.indexed)
        (
          'Batch ${index + 1}',
          '${weight}Kg',
          '${demoNumber(weight / lot.sugarKg * 100, decimals: 1)}%',
        ),
    ];
  }

  int _gradeKg(DemoLotFixture source) => source.batchWeights.indexed
      .where((entry) => ['A', 'B', 'C'][entry.$1 % 3] == grade)
      .fold(0, (sum, entry) => sum + entry.$2);

  final ValueChanged<NiraTab> onNavigate;

  String get title => switch (kind) {
    ReportDetailKind.rendemen => 'Detail Rendemen',
    ReportDetailKind.grade => 'Detail Grade',
    ReportDetailKind.margin => 'Margin kloter',
  };

  @override
  Widget build(BuildContext context) => ReportDetailLayout(
    title: title,
    onNavigate: onNavigate,
    children: [
      if (kind == ReportDetailKind.margin)
        _margin()
      else if (kind == ReportDetailKind.grade)
        _grade()
      else
        _rendemen(),
    ],
  );

  Widget _entityCard() => ReportEntityCard(
    code: lot.code,
    supplier: lot.supplier,
    date: formatDate(DateTime(2026, 10, lot.day)),
  );

  Widget _rendemen() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entityCard(),
      const SizedBox(height: NiraSpace.md),
      DetailMetrics([
        ('Tebu', '${demoNumber(lot.caneKg)}Kg'),
        ('Gula final', '${lot.sugarKg}Kg'),
        (
          'Rendemen',
          '${demoNumber(lot.sugarKg / lot.caneKg * 100, decimals: 1)}%',
        ),
      ]),
      const SizedBox(height: NiraSpace.lg),
      const DetailSectionTitle('Kontribusi hasil per batch'),
      const SizedBox(height: NiraSpace.xs),
      _contributionTable(),
    ],
  );

  Widget _grade() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NiraSummaryCard(
        'Nilai produksi',
        demoMoney(gradeTotal * {'A': 20000, 'B': 18000, 'C': 15000}[grade]!),
      ),
      const SizedBox(height: NiraSpace.md),
      DetailMetrics([
        ('Grade $grade', '${gradeTotal}Kg'),
        ('Kloter asal', '${contributions.length}'),
      ]),
      const SizedBox(height: NiraSpace.lg),
      Text(
        '${demoNumber(gradeTotal / ((analytics?.sugarTotal ?? lot.sugarKg) == 0 ? 1 : (analytics?.sugarTotal ?? lot.sugarKg)) * 100, decimals: 1)}% dari total ${analytics?.sugarTotal ?? lot.sugarKg} Kg',
        style: niraText(NiraType.caption, color: niraLeaf),
      ),
      const SizedBox(height: NiraSpace.sm),
      const DetailSectionTitle('Kontribusi per kloter'),
      const SizedBox(height: NiraSpace.xs),
      _contributionTable(),
    ],
  );

  Widget _margin() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entityCard(),
      const SizedBox(height: NiraSpace.md),
      DetailMetrics([
        ('Tebu', '${demoNumber(lot.caneKg)}Kg'),
        ('Gula final', '${lot.sugarKg}Kg'),
        (
          'Rendemen',
          '${demoNumber(lot.sugarKg / lot.caneKg * 100, decimals: 1)}%',
        ),
      ]),
      const SizedBox(height: NiraSpace.md),
      const DetailSectionTitle('Rincian perhitungan'),
      const SizedBox(height: NiraSpace.sm),
      ReportMoneyTable(
        rows: [
          ('Nilai produksi', demoMoney(lot.productionValue)),
          (
            'Modal tebu',
            demoMoney(-(lot.totalCost - (100000 + lot.day * 2000))),
          ),
          ('Biaya operasional', demoMoney(-(100000 + lot.day * 2000))),
        ],
        total: ('Margin Produksi', demoMoney(lot.marginRupiah)),
      ),
      const SizedBox(height: NiraSpace.lg),
      const DetailSectionTitle('Kontribusi Batch'),
      const SizedBox(height: NiraSpace.sm),
      NiraOutline(
        Padding(
          padding: const EdgeInsets.all(NiraSpace.sm),
          child: Column(
            children: [
              _moneyRow('Batch', 'Nilai', bold: true),
              ReportPaginatedList<int>(
                items: List.generate(lot.batchCount, (index) => index + 1),
                builder: (rows) => Column(
                  children: [
                    for (final i in rows)
                      _moneyRow(
                        'Batch $i',
                        demoMoney(
                          lot.batchWeights[i - 1] *
                              [20000, 18000, 15000][(i - 1) % 3],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _moneyRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: niraText(
              NiraType.body,
              weight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          value,
          style: niraText(
            NiraType.body,
            weight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _contributionTable() => ReportContributionTable(
    columns: [
      kind == ReportDetailKind.grade ? 'Kloter' : 'Batch',
      'Berat',
      'Porsi',
    ],
    rows: [
      for (final row in contributions)
        ReportContribution(row.$1, row.$2, row.$3),
    ],
    total: ReportContribution(
      'Total',
      '${kind == ReportDetailKind.grade ? gradeTotal : lot.sugarKg}Kg',
      '100%',
    ),
  );
}
