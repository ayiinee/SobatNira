import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';

class ReportDateButton extends StatelessWidget {
  const ReportDateButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Filter tanggal laporan',
    button: true,
    child: Tooltip(
      message: 'Filter tanggal laporan',
      excludeFromSemantics: true,
      child: Material(
        color: niraGreen,
        borderRadius: BorderRadius.circular(niraRadius),
        child: InkWell(
          onTap: onPressed,
          overlayColor: niraGreenOverlay,
          borderRadius: BorderRadius.circular(niraRadius),
          child: const SizedBox.square(
            dimension: 44,
            child: Center(child: NiraIcon('calendar', 22, color: Colors.white)),
          ),
        ),
      ),
    ),
  );
}
