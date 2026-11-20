import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/kloter_cane_overlay.dart';
import '../../widgets/review_status_label.dart';
import 'demo_production.dart';

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
          color: pending ? const Color(0xFFCFA331) : niraGreen,
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
                KloterCaneOverlay(pending: pending),
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
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: NiraSpace.sm,
                            runSpacing: NiraSpace.xs,
                            children: [
                              Text(
                                kloter.code,
                                style: niraText(
                                  NiraType.section,
                                  color: titleColor,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              ReviewStatusLabel(
                                pending: pending,
                                label: kloter.record == null
                                    ? null
                                    : pending
                                    ? 'Kloter terbuka'
                                    : 'Kloter tuntas',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: NiraSpace.xs),
                        Text(
                          kloter.supplier,
                          style: niraText(NiraType.body, color: foreground),
                        ),
                        const SizedBox(height: NiraSpace.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
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
                              child: Text(
                                formatDate(kloter.date),
                                textAlign: TextAlign.end,
                                style: niraText(
                                  NiraType.caption,
                                  color: foreground,
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
