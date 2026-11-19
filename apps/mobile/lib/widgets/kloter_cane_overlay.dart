import 'package:flutter/material.dart';

class KloterCaneOverlay extends StatelessWidget {
  const KloterCaneOverlay({
    this.pending = false,
    this.batch = false,
    super.key,
  });

  final bool pending;
  final bool batch;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 0,
    bottom: batch ? -20 : -28,
    child: IgnorePointer(
      child: Image.asset(
        'assets/sobatnira/art/cane.png',
        width: batch ? 104 : 120,
        height: batch ? 63 : 73,
        opacity: AlwaysStoppedAnimation(pending ? .77 : .50),
        excludeFromSemantics: true,
      ),
    ),
  );
}
