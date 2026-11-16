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
                  21,
                  niraInset,
                  17,
                ),
                child: Column(
                  children: [
                    const DetailMetrics([
                      ('Tebu bersih', '1.500Kg'),
                      ('Brix tebu', '90Kg'),
                      ('Nira tercatat', '360L'),
                    ]),
                    const SizedBox(height: 14),
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
                  14,
                  niraInset,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DetailSectionTitle('Batch kloter'),
                    const SizedBox(height: 2),
                    Text(
                      kloter.batchesToReview == 0
                          ? 'Semua batch telah ditinjau'
                          : '${kloter.batchesToReview} Batch perlu ditinjau',
                      style: niraText(
                        11.5,
                        color: kloter.batchesToReview == 0
                            ? niraLeaf
                            : niraOchre,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final batch in kloter.batches)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 13),
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
    final foreground = pending && MediaQuery.highContrastOf(context)
        ? niraGreen
        : Colors.white;
    return Material(
      color: pending ? niraGold : niraGreen,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: pending ? niraOchre : niraGreen, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: pending ? 1 : .37,
                  child: Image.asset(
                    'assets/sobatnira/art/cane.png',
                    width: 137,
                    height: 83,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 63),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: niraPaper,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Batch ${batch.number}',
                          style: niraText(
                            14.2,
                            color: pending ? niraGold : niraGreen,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      flex: 66,
                      child: Column(
                        children: [
                          _info('Nira batch', '180L', foreground),
                          const SizedBox(height: 3),
                          _info('Hasil fisik', '90Kg', foreground),
                          const SizedBox(height: 3),
                          _info(
                            'Bagian dari kloter',
                            batch.review.fields[3].display,
                            foreground,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: foreground),
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
        child: Text(label, style: niraText(11.5, color: foreground)),
      ),
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(':   $value', style: niraText(11.5, color: foreground)),
        ),
      ),
    ],
  );
}
