import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_detail_widgets.dart';
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
    final inset = niraPageInset(context);
    final physical = '${reportNumber(batch['physicalWeightKg'])} kg';
    final juice = '${reportNumber(batch['quantityMl'])} ml';
    final wok = 'Wajan ${batch['wokNumber']}';
    final occurred = DateTime.parse(batch['occurredAt'] as String).toLocal();
    final date =
        '${formatDate(occurred)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(occurred), alwaysUse24HourFormat: true)}';
    return NiraScaffold(
      tab: widget.navigationTab,
      onNavigate: widget.onNavigate,
      body: KloterDetailBody(
        section: _section,
        padding: EdgeInsets.fromLTRB(inset, NiraSpace.md, inset, NiraSpace.lg),
        header: [
          const DetailTitle('Detail batch'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              spacing: NiraSpace.sm,
              children: [
                Expanded(
                  child: Text(
                    batch['code'] as String,
                    style: niraText(NiraType.title, weight: FontWeight.w700),
                  ),
                ),
                BatchReviewBadge(reviewed: widget.reviewed),
              ],
            ),
          ),
          NiraTabs(
            labels: const ['Ringkasan', 'Masak', 'Grade'],
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
            height: 44,
            inset: 12,
          ),
        ],
        children: switch (_section) {
          0 => [
            Text(
              '${widget.lotCode} · ${widget.source}',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
            const SizedBox(height: NiraSpace.sm),
            if (widget.hasReport) ...[
              NiraSummaryCard(
                'Nilai produksi batch',
                reportMoney(batch['exactValueRupiah']),
              ),
              const SizedBox(height: NiraSpace.sm),
              Text(
                'Nilai batch sebelum pembulatan per kloter.',
                style: niraText(NiraType.caption, color: niraLeaf),
              ),
            ],
            const SizedBox(height: NiraSpace.md),
            DetailMetrics([
              if (widget.hasReport)
                ('Gula grade sah', '${reportNumber(batch['finalSugarKg'])} kg'),
              ('Hasil fisik', physical),
              ('Nira dimasak', juice),
            ]),
            ...widget.marginDetails,
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
            for (final grade in (batch['grades'] as List? ?? []).cast<Json>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Grade ${grade['code']}'),
                subtitle: Text(
                  '${reportNumber(grade['weightKg'])} kg · ${reportMoney(grade['pricePerKgRupiah'])}/kg',
                ),
                trailing: Text(reportMoney(grade['exactValueRupiah'])),
              ),
          ],
        },
      ),
    );
  }
}
