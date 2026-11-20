import 'dart:typed_data';

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
    this.loadStock,
    this.production,
    this.onEdit,
    this.onTransfer,
    this.onClosure,
    this.onOpenPekerjaan,
    this.onReturnFromProcess,
    this.approvedPhoto,
    this.statusMessage,
    super.key,
  });

  final DemoKloter kloter;
  final DemoProduction demo;
  final ValueChanged<NiraTab> onNavigate;
  final Future<Map<String, dynamic>> Function()? loadStock;
  final Widget? production;
  final Future<bool> Function()? onEdit;
  final Future<void> Function()? onTransfer;
  final Future<void> Function()? onClosure;
  final VoidCallback? onOpenPekerjaan;
  final VoidCallback? onReturnFromProcess;
  final Future<Uint8List?> Function(String)? approvedPhoto;
  final Widget? statusMessage;

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
              const SizedBox(height: NiraSpace.md),
              KloterHeading(kloter),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  niraPageInset(context),
                  NiraSpace.md,
                  niraPageInset(context),
                  NiraSpace.lg,
                ),
                child: Column(
                  children: [
                    DetailMetrics([
                      (
                        'Tebu bersih',
                        kloter.record != null && kloter.netWeightKg == null
                            ? '—'
                            : kloter.weight,
                      ),
                      (
                        'Brix tebu',
                        kloter.brix == null
                            ? '—'
                            : formatQuantity(kloter.brix, '°Bx'),
                      ),
                      if (kloter.record == null)
                        (
                          'Nira tercatat',
                          formatQuantity(kloter.batchJuiceLiters, 'L'),
                        )
                      else
                        (
                          'Nira tercatat',
                          kloter.juiceLiters == null
                              ? '—'
                              : formatQuantity(kloter.juiceLiters, 'L'),
                        ),
                    ], centerAll: true),
                    ?statusMessage,
                    const SizedBox(height: NiraSpace.lg),
                    DocumentLink('Data tebu dan penggilingan', () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KloterProcessPage(
                            demo: demo,
                            kloter: kloter,
                            onNavigate: onNavigate,
                            onOpenPekerjaan: onOpenPekerjaan,
                            approvedPhoto: approvedPhoto,
                            loadStock: loadStock,
                            onEdit: onEdit,
                            onTransfer: onTransfer,
                            onClosure: onClosure,
                          ),
                        ),
                      );
                      onReturnFromProcess?.call();
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
                padding: EdgeInsets.fromLTRB(
                  niraPageInset(context),
                  NiraSpace.lg,
                  niraPageInset(context),
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
                        child: KloterBatchTile(
                          title: 'Batch ${batch.number}',
                          juice: batch.juice.display,
                          physicalWeight: batch.physicalWeight.display,
                          pending: !batch.review.verified,
                          onTap: () => Navigator.of(context).push(
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

class KloterBatchTile extends StatelessWidget {
  const KloterBatchTile({
    required this.title,
    required this.juice,
    required this.physicalWeight,
    required this.pending,
    required this.onTap,
    this.cancelled = false,
    super.key,
  });

  final String title;
  final String juice;
  final String physicalWeight;
  final bool pending;
  final VoidCallback onTap;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    const foreground = Colors.white;
    final status = cancelled
        ? 'Dibatalkan'
        : pending
        ? 'Perlu ditinjau'
        : 'Tervalidasi';
    final heading = Text(
      title,
      style: niraText(
        NiraType.section,
        color: pending ? foreground : niraYellow,
        weight: FontWeight.w700,
      ),
    );
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _info(context, 'Nira batch', juice, foreground),
        const SizedBox(height: 2),
        _info(context, 'Hasil fisik', physicalWeight, foreground),
      ],
    );
    return Semantics(
      label: '$title, $status',
      button: true,
      child: Material(
        color: pending ? niraGold : niraGreen,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(niraRadius),
          side: BorderSide(color: pending ? niraOchre : niraGreen),
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: heading),
                          const SizedBox(width: NiraSpace.sm),
                          Expanded(
                            flex: 2,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: ReviewStatusLabel(
                                pending: pending || cancelled,
                                label: status,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: NiraSpace.xs / 2),
                      details,
                    ],
                  ),
                ),
              ),
            ],
          ),
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
