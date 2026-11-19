import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/kloter_cane_overlay.dart';
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
  Widget build(BuildContext context) => NiraScaffold(
    tab: NiraTab.laporan,
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
        if (kind == ReportDetailKind.margin)
          _margin()
        else if (kind == ReportDetailKind.grade)
          _grade()
        else
          _rendemen(),
      ],
    ),
  );

  Widget _entityCard() => Container(
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
                lot.code,
                style: niraText(
                  NiraType.title,
                  color: niraYellow,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                lot.supplier,
                style: niraText(NiraType.body, color: Colors.white),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                formatDate(DateTime(2026, 10, lot.day)),
                style: niraText(NiraType.caption, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
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
      NiraOutline(
        Padding(
          padding: const EdgeInsets.all(NiraSpace.sm),
          child: Column(
            children: [
              _moneyRow('Komponen', 'Nilai', bold: true),
              _moneyRow('Nilai produksi', demoMoney(lot.productionValue)),
              _moneyRow(
                'Modal tebu',
                demoMoney(-(lot.totalCost - (100000 + lot.day * 2000))),
              ),
              _moneyRow(
                'Biaya operasional',
                demoMoney(-(100000 + lot.day * 2000)),
              ),
              const Divider(height: 12, thickness: 1, color: niraLine),
              _moneyRow(
                'Margin Produksi',
                demoMoney(lot.marginRupiah),
                bold: true,
              ),
            ],
          ),
        ),
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

  Widget _contributionTable() => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(NiraSpace.sm),
      child: Column(
        children: [
          _tableRow(
            kind == ReportDetailKind.grade ? 'Kloter' : 'Batch',
            'Berat',
            'Porsi',
            header: true,
          ),
          if (kind == ReportDetailKind.grade)
            ReportPaginatedList<(String, String, String)>(
              items: contributions,
              resetToken: kind,
              builder: (rows) => Column(
                children: [
                  for (final row in rows) _tableRow(row.$1, row.$2, row.$3),
                ],
              ),
            )
          else
            for (final row in contributions) _tableRow(row.$1, row.$2, row.$3),
          const Divider(height: 10),
          _tableRow(
            'Total',
            '${kind == ReportDetailKind.grade ? gradeTotal : lot.sugarKg}Kg',
            '100%',
            header: true,
          ),
        ],
      ),
    ),
  );

  Widget _tableRow(
    String one,
    String two,
    String three, {
    bool header = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            one,
            style: niraText(
              NiraType.body,
              weight: header ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Expanded(
          child: Text(
            two,
            style: niraText(
              NiraType.body,
              weight: header ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Expanded(
          child: Text(
            three,
            textAlign: TextAlign.end,
            style: niraText(
              NiraType.body,
              weight: header ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}
