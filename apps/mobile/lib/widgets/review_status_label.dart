import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';

class ReviewStatusLabel extends StatelessWidget {
  const ReviewStatusLabel({required this.pending, this.label, super.key});
  final bool pending;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x26000000),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            pending ? Icons.schedule_rounded : Icons.check_circle_rounded,
            color: Colors.white,
            size: 12,
          ),
        ),
        const SizedBox(width: NiraSpace.xs),
        Flexible(
          child: Text(
            label ?? (pending ? 'Perlu ditinjau' : 'Tervalidasi'),
            style: niraText(
              NiraType.caption,
              color: Colors.white,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
