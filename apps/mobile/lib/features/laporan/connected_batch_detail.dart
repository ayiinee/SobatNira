import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_detail_widgets.dart';
import '../kloter/batch_detail_layout.dart';
import '../kloter/juice_volume.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';

class ConnectedBatchDetail extends StatefulWidget {
  const ConnectedBatchDetail({
    required this.batch,
    required this.lotCode,
    required this.source,
    required this.marginDetails,
    required this.onNavigate,
    required this.navigationTab,
    this.reviewed = true,
    this.hasReport = true,
    super.key,
  });

  final Json batch;
  final String lotCode, source;
  final List<Widget> marginDetails;
  final ValueChanged<NiraTab> onNavigate;
  final NiraTab navigationTab;
  final bool reviewed, hasReport;

  @override
  State<ConnectedBatchDetail> createState() => _ConnectedBatchDetailState();
}

class _ConnectedBatchDetailState extends State<ConnectedBatchDetail> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final physical = '${reportNumber(batch['physicalWeightKg'])} kg';
    final juice =
        '${reportNumber(millilitersToLiters(batch['quantityMl'].toString()))} L';
    final wok = 'Wajan ${batch['wokNumber']}';
    final occurred = DateTime.parse(batch['occurredAt'] as String).toLocal();
    final date =
        '${formatDate(occurred)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(occurred), alwaysUse24HourFormat: true)}';
    return BatchDetailLayout(
      code: batch['code'] as String,
      reviewed: widget.reviewed,
      section: _section,
      onSection: (value) => setState(() => _section = value),
      tab: widget.navigationTab,
      onNavigate: widget.onNavigate,
      children: switch (_section) {
        0 => [
          Text(
            '${widget.lotCode} · ${widget.source}',
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
          const SizedBox(height: NiraSpace.sm),
          BatchSummarySection(
            fields: EditableFields(
              fields: [
                DemoField('Nira yang dimasak', juice),
                DemoField('Wajan', wok),
                DemoField('Waktu masak', date),
                DemoField('Hasil timbang', physical),
                if (widget.hasReport)
                  DemoField(
                    'Gula grade sah',
                    '${reportNumber(batch['finalSugarKg'])} kg',
                  ),
              ],
              onEdit: null,
            ),
            prices: [
              if (!widget.hasReport)
                const Text('Rincian grade belum tersedia di laporan.'),
              for (final grade in (batch['grades'] as List? ?? []).cast<Json>())
                BatchPriceRow(
                  grade: Text(
                    'Grade ${grade['code']}',
                    style: niraText(NiraType.body),
                  ),
                  weight: Text(
                    '${reportNumber(grade['weightKg'])} kg',
                    style: niraText(NiraType.body),
                  ),
                  price: Text(
                    reportMoney(grade['pricePerKgRupiah']),
                    style: niraText(NiraType.body),
                  ),
                  height: 30,
                ),
            ],
            total: BatchPriceRow(
              grade: Text(
                'Nilai produksi batch',
                style: niraText(NiraType.caption, weight: FontWeight.w700),
              ),
              weight: Text(
                widget.hasReport
                    ? '${reportNumber(batch['finalSugarKg'])} kg'
                    : '—',
                style: niraText(NiraType.body),
              ),
              price: Text(
                widget.hasReport ? reportMoney(batch['exactValueRupiah']) : '—',
                style: niraText(NiraType.section, weight: FontWeight.w700),
              ),
              height: 32,
              line: niraGold,
            ),
            footer: widget.marginDetails,
          ),
        ],
        1 => [
          const DetailSectionTitle('Data pemasakan'),
          const SizedBox(height: NiraSpace.sm),
          DetailMetrics([('Wajan', wok), ('Nira dimasak', juice)]),
          const SizedBox(height: NiraSpace.sm),
          Text('Waktu masak: $date'),
        ],
        _ => [
          const DetailSectionTitle('Hasil dan Grade'),
          const SizedBox(height: NiraSpace.sm),
          DetailMetrics([('Hasil fisik', physical)]),
          if (!widget.hasReport)
            const Text('Rincian grade belum tersedia di laporan.'),
          const BatchPriceHeader(),
          for (final grade in (batch['grades'] as List? ?? []).cast<Json>())
            BatchPriceRow(
              grade: Text(
                'Grade ${grade['code']}',
                style: niraText(NiraType.body),
              ),
              weight: Text(
                '${reportNumber(grade['weightKg'])} kg',
                style: niraText(NiraType.body),
              ),
              price: Text(
                '${reportMoney(grade['pricePerKgRupiah'])}/kg',
                style: niraText(NiraType.body),
              ),
            ),
        ],
      },
    );
  }
}
