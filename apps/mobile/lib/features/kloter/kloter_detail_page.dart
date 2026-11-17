import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'batch_detail_page.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';
import 'kloter_process_page.dart';

class KloterDetailPage extends StatelessWidget {
  const KloterDetailPage({
    required this.kloter,
    required this.demo,
    required this.onNavigate,
    super.key,
  });

  final DemoKloter kloter;
  final DemoProduction demo;
  final ValueChanged<NiraTab> onNavigate;

  @override
  Widget build(BuildContext context) => NiraScaffold(
    tab: NiraTab.kloter,
    onNavigate: onNavigate,
    body: ListenableBuilder(
      listenable: demo,
      builder: (context, _) => CustomScrollView(
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
                    const DetailMetrics([
                      ('Tebu bersih', '1.500Kg'),
                      ('Brix tebu', '90Kg'),
                      ('Nira tercatat', '360L'),
                    ]),
                    const SizedBox(height: NiraSpace.lg),
                    DocumentLink('Data tebu dan penggilingan', () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KloterProcessPage(
                            demo: demo,
                            kloter: kloter,
                            onNavigate: onNavigate,
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
                    Text(
                      kloter.batchesToReview == 0
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
            Positioned(
              right: 0,
              bottom: -20,
              child: IgnorePointer(
                child: Opacity(
                  opacity: pending ? .65 : .30,
                  child: Image.asset(
                    'assets/sobatnira/art/cane.png',
                    width: 104,
                    height: 63,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 63),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NiraSpace.md,
                  vertical: NiraSpace.sm,
                ),
                child:
                    MediaQuery.textScalerOf(context).scale(NiraType.body) > 17
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Batch ${batch.number}',
                                  style: niraText(
                                    NiraType.section,
                                    color: pending ? foreground : niraYellow,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: foreground,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: NiraSpace.sm),
                          _info('Nira batch', '180L', foreground),
                          const SizedBox(height: NiraSpace.xs),
                          _info('Hasil fisik', '90Kg', foreground),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 24,
                            child: Text(
                              'Batch ${batch.number}',
                              style: niraText(
                                NiraType.section,
                                color: pending ? foreground : niraYellow,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: NiraSpace.xs),
                          Expanded(
                            flex: 66,
                            child: Column(
                              children: [
                                _info('Nira batch', '180L', foreground),
                                const SizedBox(height: NiraSpace.xs),
                                _info('Hasil fisik', '90Kg', foreground),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: foreground,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value, Color foreground) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: Text(label, style: niraText(NiraType.body, color: foreground)),
      ),
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.only(left: NiraSpace.xs),
          child: Text(
            ':   $value',
            style: niraText(NiraType.body, color: foreground),
          ),
        ),
      ),
    ],
  );
}
