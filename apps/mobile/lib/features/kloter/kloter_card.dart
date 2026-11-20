import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/review_status_label.dart';
import 'demo_production.dart';

double caneOverlayOpacity(bool pending) => pending ? .82 : .55;

class KloterCard extends StatelessWidget {
  const KloterCard({required this.kloter, required this.onTap, super.key});

  final DemoKloter kloter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pending = kloter.status == KloterStatus.review;
    const foreground = Colors.white;
    final titleColor = pending ? foreground : niraYellow;
    final status = kloter.record == null
        ? (pending ? 'Perlu ditinjau' : 'Tervalidasi')
        : (pending ? 'Kloter terbuka' : 'Kloter tuntas');
    return Semantics(
      label: '${kloter.code}, $status',
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: const [niraShadow],
          borderRadius: BorderRadius.circular(niraRadius),
        ),
        child: Material(
          color: pending ? niraGold : niraGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(niraRadius),
            side: BorderSide(
              color: pending
                  ? const Color(0xFFB97105)
                  : const Color(0xFF286348),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            overlayColor: niraGreenOverlay,
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: -28,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: caneOverlayOpacity(pending),
                      child: Image.asset(
                        'assets/sobatnira/art/cane.png',
                        width: 120,
                        height: 73,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 83),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NiraSpace.md,
                      vertical: NiraSpace.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                kloter.code,
                                style: niraText(
                                  NiraType.section,
                                  color: titleColor,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: NiraSpace.sm),
                            Expanded(
                              flex: 2,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: ReviewStatusLabel(pending: pending),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NiraSpace.xs / 2),
                        Text(
                          kloter.supplier,
                          style: niraText(NiraType.body, color: foreground),
                        ),
                        const SizedBox(height: NiraSpace.xs / 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                kloter.weight,
                                style: niraText(
                                  NiraType.body,
                                  color: foreground,
                                ),
                              ),
                            ),
                            const SizedBox(width: NiraSpace.sm),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: ReviewStatusLabel.horizontalPadding,
                                ),
                                child: Text(
                                  formatDate(kloter.date),
                                  textAlign: TextAlign.end,
                                  style: niraText(
                                    NiraType.caption,
                                    color: foreground,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
