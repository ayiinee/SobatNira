import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/kloter_cane_overlay.dart';
import '../../widgets/review_status_label.dart';
import 'batch_detail_page.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';
import 'kloter_process_page.dart';

class KloterDetailPage extends StatelessWidget {
  const KloterDetailPage({
    required this.kloter,
    required this.demo,
    required this.onNavigate,
    this.stock,
    this.production,
    this.onEdit,
    this.onTransfer,
    this.onClosure,
    this.onOpenPekerjaan,
    super.key,
  });

  final DemoKloter kloter;
  final DemoProduction demo;
  final ValueChanged<NiraTab> onNavigate;
  final Widget? stock;
  final Widget? production;
  final VoidCallback? onEdit;
  final VoidCallback? onTransfer;
  final VoidCallback? onClosure;
  final VoidCallback? onOpenPekerjaan;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: demo,
    builder: (context, _) => NiraScaffold(
      tab: NiraTab.kloter,
      onNavigate: onNavigate,
      body: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              const DetailTitle('Detail kloter'),
              KloterHeading(kloter),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  niraInset,
                  NiraSpace.xl,
                  niraInset,
                  NiraSpace.lg,
                ),
                child: Column(
                  children: [
                    DetailMetrics(
                      kloter.record == null
                          ? const [
                              ('Tebu bersih', '1.500Kg'),
                              ('Brix tebu', '90Kg'),
                              ('Nira tercatat', '360L'),
                            ]
                          : [
                              ('Tebu bersih', kloter.weight),
                              ('Brix tebu', formatQuantity(kloter.brix, '°Bx')),
                              (
                                'Nira dihasilkan',
                                formatQuantity(kloter.juiceLiters, 'L'),
                              ),
                            ],
                    ),
                    if (stock != null) ...[
                      const SizedBox(height: NiraSpace.md),
                      stock!,
                    ],
                    if (onEdit != null) DocumentLink('Edit kloter', onEdit!),
                    if (onTransfer != null)
                      DocumentLink('Transfer nira', onTransfer!),
                    if (onClosure != null)
                      DocumentLink('Penutupan dan riwayat', onClosure!),
                    const SizedBox(height: NiraSpace.lg),
                    DocumentLink('Data tebu dan penggilingan', () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KloterProcessPage(
                            demo: demo,
                            kloter: kloter,
                            onNavigate: onNavigate,
                            onOpenPekerjaan: onOpenPekerjaan,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                border: Border(
                  top: BorderSide(color: niraGreen, width: 1.15),
                  left: BorderSide(color: niraGreen, width: 1.15),
                  right: BorderSide(color: niraGreen, width: 1.15),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  niraInset,
                  NiraSpace.lg,
                  niraInset,
                  NiraSpace.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DetailSectionTitle('Batch kloter'),
                    const SizedBox(height: NiraSpace.xs),
                    if (production != null)
                      production!
                    else
                      Text(
                        kloter.id != null
                            ? 'Rincian batch resmi belum tersedia.'
                            : kloter.batchesToReview == 0
                            ? 'Semua batch telah ditinjau'
                            : '${kloter.batchesToReview} Batch perlu ditinjau',
                        style: niraText(
                          NiraType.caption,
                          color: kloter.batchesToReview == 0
                              ? niraLeaf
                              : niraOchre,
                        ),
                      ),
                    const SizedBox(height: NiraSpace.md),
                    for (final batch in kloter.batches)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NiraSpace.md),
                        child: _BatchTile(
                          batch,
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BatchDetailPage(
                                batch: batch,
                                kloterCode: kloter.code,
                                demo: demo,
                                onNavigate: onNavigate,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BatchTile extends StatelessWidget {
  const _BatchTile(this.batch, this.onTap);

  final DemoBatch batch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pending = !batch.review.verified;
    const foreground = Colors.white;
    return Material(
      color: pending ? niraGold : niraGreen,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(niraRadius),
        side: BorderSide(color: pending ? niraOchre : niraGreen, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        overlayColor: niraGreenOverlay,
        child: Stack(
          children: [
            KloterCaneOverlay(pending: pending, batch: true),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 63),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NiraSpace.md,
                  vertical: NiraSpace.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: NiraSpace.sm,
                      runSpacing: NiraSpace.xs,
                      children: [
                        Text(
                          'Batch ${batch.number}',
                          style: niraText(
                            NiraType.section,
                            color: pending ? foreground : niraYellow,
                            weight: FontWeight.w700,
                          ),
                        ),
                        ReviewStatusLabel(pending: pending),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _info(context, 'Nira batch', '180L', foreground),
                    const SizedBox(height: 2),
                    _info(context, 'Hasil fisik', '90Kg', foreground),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(
    BuildContext context,
    String label,
    String value,
    Color foreground,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: MediaQuery.textScalerOf(context).scale(14) * 5.2,
        child: Text(label, style: niraText(NiraType.body, color: foreground)),
      ),
      const SizedBox(width: NiraSpace.xs),
      Text(':', style: niraText(NiraType.body, color: foreground)),
      const SizedBox(width: NiraSpace.xs),
      Expanded(
        child: Text(value, style: niraText(NiraType.body, color: foreground)),
      ),
    ],
  );
}
