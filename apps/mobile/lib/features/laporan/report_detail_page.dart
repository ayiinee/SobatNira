import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/kloter_cane_overlay.dart';
import '../../widgets/summary_card.dart';
import '../kloter/kloter_detail_widgets.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';
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
    this.report,
    this.officialLot,
    this.batchId,
    super.key,
  });

  final ReportDetailKind kind;
  final AnalyticsRow? row;
  final DemoAnalytics? analytics;
  final Json? report;
  final Json? officialLot;
  final String? batchId;
  Json? get calculation => officialLot?['calculation'] as Json?;
  Json? get gradeResult => (report?['grades'] as List?)
      ?.cast<Json>()
      .where((entry) => entry['code'] == grade)
      .firstOrNull;
  List<Json> get officialBatches =>
      (officialLot?['batches'] as List? ?? const [])
          .cast<Json>()
          .where((batch) => batchId == null || batch['id'] == batchId)
          .toList();
  DemoLotFixture get lot => demoLotFor(
    row?.code.isNotEmpty == true ? row!.code : demoLotFixtures.first.code,
  );
  String get grade => row?.supplier.startsWith('Grade ') == true
      ? row!.supplier.substring(6)
      : 'A';
  String get displayedSugar =>
      report == null ? '${lot.sugarKg}Kg' : _kg(calculation?['finalSugarKg']);
  String get displayedGrade =>
      report == null ? '${gradeTotal}Kg' : _kg(gradeResult?['weightKg']);

  List<(String, String)> get lotMetrics => report == null
      ? [
          ('Tebu', '${demoNumber(lot.caneKg)}Kg'),
          ('Gula final', displayedSugar),
          (
            'Rendemen',
            '${demoNumber(lot.sugarKg / lot.caneKg * 100, decimals: 1)}%',
          ),
        ]
      : [
          ('Tebu', _kg(officialLot?['caneNetKg'])),
          ('Gula final', displayedSugar),
          (
            'Rendemen',
            calculation == null
                ? '—'
                : '${reportNumber(calculation!['rendemenPercent'])}%',
          ),
        ];
  int get gradeTotal =>
      analytics?.gradeWeight(grade) ??
      lot.batchWeights.indexed
          .where((entry) => ['A', 'B', 'C'][entry.$1 % 3] == grade)
          .fold(0, (sum, entry) => sum + entry.$2);
  List<(String, String, String)> get contributions {
    if (report != null) return _officialContributions();
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

  List<(String, String, String)> _officialContributions() {
    if (kind != ReportDetailKind.grade) {
      return [
        for (final batch in officialBatches)
          (
            batch['code'] as String,
            _kg(batch['finalSugarKg']),
            reportShare(batch['finalSugarKg'], calculation?['finalSugarKg']),
          ),
      ];
    }
    final rows = <(String, String, String)>[];
    for (final lot in (report!['items'] as List).cast<Json>()) {
      var weight = 0.0;
      for (final batch in (lot['batches'] as List).cast<Json>()) {
        for (final item in (batch['grades'] as List).cast<Json>()) {
          if (item['code'] == grade) {
            weight += double.parse('${item['weightKg']}');
          }
        }
      }
      if (weight > 0) {
        final formatted = weight.toStringAsFixed(6);
        rows.add((
          lot['code'] as String,
          _kg(formatted),
          reportShare(formatted, gradeResult?['weightKg']),
        ));
      }
    }
    return rows;
  }

  String _kg(Object? value) =>
      value == null ? '—' : '${reportNumber(value)} kg';

  String _cost(String key) {
    final costs = calculation?['costs'] as Json?;
    final value = costs?[key];
    return value == null
        ? '—'
        : reportMoney('${value == '0' ? '' : '-'}$value');
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
      padding: const EdgeInsets.fromLTRB(
        niraInset,
        NiraSpace.sm,
        niraInset,
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
                officialLot?['code'] as String? ?? lot.code,
                style: niraText(
                  NiraType.title,
                  color: niraYellow,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                officialLot?['supplier'] as String? ?? lot.supplier,
                style: niraText(NiraType.body, color: Colors.white),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                formatDate(
                  officialLot == null
                      ? DateTime(2026, 10, lot.day)
                      : DateTime.parse(
                          officialLot!['receivedAt'] as String,
                        ).toLocal(),
                ),
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
      DetailMetrics(lotMetrics),
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
        report == null
            ? demoMoney(
                gradeTotal * {'A': 20000, 'B': 18000, 'C': 15000}[grade]!,
              )
            : reportMoney(gradeResult?['exactValueRupiah']),
      ),
      const SizedBox(height: NiraSpace.md),
      DetailMetrics([
        ('Grade $grade', displayedGrade),
        ('Kloter asal', '${contributions.length}'),
      ]),
      const SizedBox(height: NiraSpace.lg),
      Text(
        report == null
            ? '${demoNumber(gradeTotal / ((analytics?.sugarTotal ?? lot.sugarKg) == 0 ? 1 : (analytics?.sugarTotal ?? lot.sugarKg)) * 100, decimals: 1)}% dari total ${analytics?.sugarTotal ?? lot.sugarKg} Kg'
            : '${row?.secondary ?? '—'} dari total ${_kg((report!['totals'] as Json)['finalSugarKg'])}',
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
      DetailMetrics(lotMetrics),
      const SizedBox(height: NiraSpace.md),
      const DetailSectionTitle('Rincian perhitungan'),
      const SizedBox(height: NiraSpace.sm),
      NiraOutline(
        Padding(
          padding: const EdgeInsets.all(NiraSpace.sm),
          child: Column(
            children: [
              _moneyRow('Komponen', 'Nilai', bold: true),
              _moneyRow(
                'Nilai produksi',
                report == null
                    ? demoMoney(lot.productionValue)
                    : calculation == null
                    ? '—'
                    : reportMoney(calculation!['productionValueRupiah']),
              ),
              _moneyRow(
                'Modal tebu',
                report == null
                    ? demoMoney(-(lot.totalCost - (100000 + lot.day * 2000)))
                    : _cost('caneRupiah'),
              ),
              _moneyRow(
                'Biaya operasional',
                report == null
                    ? demoMoney(-(100000 + lot.day * 2000))
                    : _cost('operationalRupiah'),
              ),
              if (report != null) ...[
                _moneyRow('Biaya bahan', _cost('ingredientRupiah')),
                _moneyRow('Biaya lain', _cost('otherRupiah')),
              ],
              const Divider(height: 12, thickness: 1, color: niraLine),
              _moneyRow(
                'Margin Produksi',
                report == null
                    ? demoMoney(lot.marginRupiah)
                    : calculation == null
                    ? '—'
                    : reportMoney(calculation!['productionMarginRupiah']),
                bold: true,
              ),
            ],
          ),
        ),
      ),
      if (calculation != null && officialLot?['closed'] == false)
        Text(
          'Margin sementara untuk kloter yang masih terbuka.',
          style: niraText(NiraType.caption, color: niraLeaf),
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
              ReportPaginatedList<(String, String)>(
                items: report == null
                    ? [
                        for (var i = 0; i < lot.batchCount; i++)
                          (
                            'Batch ${i + 1}',
                            demoMoney(
                              lot.batchWeights[i] *
                                  [20000, 18000, 15000][i % 3],
                            ),
                          ),
                      ]
                    : [
                        for (final batch in officialBatches)
                          (
                            batch['code'] as String,
                            reportMoney(batch['exactValueRupiah']),
                          ),
                      ],
                builder: (rows) => Column(
                  children: [for (final row in rows) _moneyRow(row.$1, row.$2)],
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
            kind == ReportDetailKind.grade ? displayedGrade : displayedSugar,
            contributions.isEmpty ? '—' : '100%',
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
