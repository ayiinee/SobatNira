import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_detail_widgets.dart';

enum ReportDetailKind { rendemen, grade, margin }

class ReportDetailPage extends StatelessWidget {
  const ReportDetailPage({
    required this.kind,
    required this.onNavigate,
    super.key,
  });

  final ReportDetailKind kind;
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

  Widget _greenCard(String heading, String value, String caption) => Container(
    padding: const EdgeInsets.fromLTRB(
      NiraSpace.md,
      NiraSpace.sm,
      NiraSpace.md,
      NiraSpace.md,
    ),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: niraText(
            NiraType.section,
            color: niraYellow,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: NiraSpace.xs),
        Text(
          value,
          style: niraText(
            NiraType.metric,
            color: niraYellow,
            weight: FontWeight.w700,
          ),
        ),
        if (caption.isNotEmpty)
          Text(caption, style: niraText(NiraType.caption, color: Colors.white)),
      ],
    ),
  );

  Widget _entityCard() => Container(
    padding: const EdgeInsets.all(NiraSpace.lg),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MJT-260926-1A',
          style: niraText(
            NiraType.title,
            color: niraYellow,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: NiraSpace.xs),
        Text('Sugeng', style: niraText(NiraType.body, color: Colors.white)),
        const SizedBox(height: NiraSpace.xs),
        Text(
          '16 Oktober 2026',
          style: niraText(NiraType.caption, color: Colors.white),
        ),
      ],
    ),
  );

  Widget _rendemen() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entityCard(),
      const SizedBox(height: NiraSpace.md),
      const DetailMetrics([
        ('Tebu', '1.500Kg'),
        ('Gula final', '90Kg'),
        ('Rendemen', '6,0%'),
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
      _greenCard('Nilai produksi', 'Rp3.600.000', ''),
      const SizedBox(height: NiraSpace.md),
      const DetailMetrics([('Grade A', '360Kg'), ('Kloter asal', '4')]),
      const SizedBox(height: NiraSpace.lg),
      Text(
        '50,0% dari total 360 Kg',
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
      const DetailMetrics([
        ('Tebu', '1.500Kg'),
        ('Gula final', '90Kg'),
        ('Rendemen', '6,0%'),
      ]),
      const SizedBox(height: NiraSpace.md),
      const DetailSectionTitle('Rincian perhitungan'),
      _moneyRow('Nilai produksi', 'Rp1.750.000'),
      _moneyRow('Modal tebu', '-Rp1.000.000'),
      _moneyRow('Biaya operasional', '-Rp180.000'),
      const Divider(height: 12),
      _moneyRow('Margin Produksi', 'Rp570.000', bold: true),
      const SizedBox(height: NiraSpace.md),
      const DetailSectionTitle('Kontribusi Batch'),
      _moneyRow('Wajan 1', 'Rp600.000'),
      _moneyRow('Wajan 2', 'Rp600.000'),
      _moneyRow('Wajan 3', 'Rp600.000'),
      _moneyRow('Wajan 4', 'Rp600.000'),
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
          _tableRow('Batch', 'Berat', 'Porsi', header: true),
          for (final row in const [
            ('Sugeng', '90Kg', '25,0%'),
            ('Slamet', '90Kg', '25,0%'),
            ('Darto', '90Kg', '25,0%'),
            ('Mulyanto', '90Kg', '25,0%'),
          ])
            _tableRow(row.$1, row.$2, row.$3),
          const Divider(height: 10),
          _tableRow('Total', '180Kg', '100%', header: true),
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
