import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';

class KloterCard extends StatelessWidget {
  const KloterCard({required this.kloter, required this.onTap, super.key});

  final DemoKloter kloter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pending = kloter.status == KloterStatus.review;
    final highContrast = MediaQuery.highContrastOf(context);
    final foreground = pending && highContrast ? niraGreen : Colors.white;
    final titleColor = pending ? foreground : niraYellow;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: const [niraShadow],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: pending ? niraGold : niraGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: pending ? const Color(0xFFB97105) : const Color(0xFF286348),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: 0,
                bottom: 0,
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
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 83),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
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
                                17.65,
                                color: titleColor,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  formatDate(kloter.date),
                                  textAlign: TextAlign.end,
                                  style: niraText(11.8, color: foreground),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        kloter.supplier,
                        style: niraText(14.7, color: foreground),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        kloter.weight,
                        style: niraText(14.7, color: foreground),
                      ),
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
}
