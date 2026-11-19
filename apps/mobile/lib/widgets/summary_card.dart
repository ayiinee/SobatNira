import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';

const niraSummaryGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0B231A), Color(0xFF205D42), niraGreen],
  stops: [0, .6, 1],
);

class NiraSummaryCard extends StatelessWidget {
  const NiraSummaryCard(
    this.label,
    this.value, {
    this.boxes = false,
    this.cane = false,
    this.compactValue = false,
    super.key,
  });

  final String label;
  final String value;
  final bool boxes;
  final bool cane;
  final bool compactValue;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(niraRadius),
      gradient: niraSummaryGradient,
    ),
    child: Stack(
      children: [
        if (cane)
          Positioned(
            right: -9,
            top: 0,
            bottom: 0,
            width: 153,
            child: IgnorePointer(
              child: Image.asset(
                'assets/sobatnira/art/hero-cane.png',
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                opacity: const AlwaysStoppedAnimation(.24),
                excludeFromSemantics: true,
              ),
            ),
          )
        else
          Positioned(
            bottom: -12,
            right: -19,
            child: IgnorePointer(
              child: boxes
                  ? const SizedBox.square(
                      dimension: 80,
                      child: CustomPaint(painter: _BoxOverlayPainter()),
                    )
                  : const Icon(
                      Icons.layers_outlined,
                      color: Color(0x20FFFFFF),
                      size: 80,
                    ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NiraSpace.lg,
            NiraSpace.lg,
            NiraSpace.md,
            NiraSpace.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.left,
                  style: niraText(
                    NiraType.caption,
                    color: Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: NiraSpace.xs),
                if (compactValue)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _valueText(NiraType.title),
                  )
                else
                  _valueText(NiraType.metric),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _valueText(double fontSize) => Text(
    value,
    textAlign: TextAlign.left,
    style: niraText(fontSize, color: niraYellow, weight: FontWeight.w700),
  );
}

class _BoxOverlayPainter extends CustomPainter {
  const _BoxOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 388, size.height / 388);
    final paint = Paint()..color = const Color(0x20FFFFFF);
    // Trace the reference's cube faces without its editor grid or handles.
    for (final face in const [
      [Offset(204, 0), Offset(320, 8), Offset(384, 111), Offset(268, 104)],
      [
        Offset(193, 18),
        Offset(254, 113),
        Offset(216, 180),
        Offset(165, 152),
        Offset(140, 115),
      ],
      [
        Offset(268, 123),
        Offset(375, 128),
        Offset(322, 225),
        Offset(235, 223),
        Offset(234, 191),
      ],
      [Offset(7, 204), Offset(112, 148), Offset(216, 204), Offset(112, 260)],
      [Offset(7, 224), Offset(102, 277), Offset(102, 386), Offset(7, 335)],
      [Offset(122, 277), Offset(216, 224), Offset(216, 335), Offset(123, 386)],
      [Offset(311, 283), Offset(349, 322), Offset(311, 362), Offset(273, 322)],
      [Offset(248, 344), Offset(266, 362), Offset(248, 381), Offset(230, 362)],
    ]) {
      canvas.drawPath(Path()..addPolygon(face, true), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BoxOverlayPainter oldDelegate) => false;
}

/// Uses the same spacing and text-scaling breakpoint on Beranda and Laporan.
class NiraSummaryPair extends StatelessWidget {
  const NiraSummaryPair({required this.first, required this.second, super.key});

  final NiraSummaryCard first;
  final NiraSummaryCard second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth <
          MediaQuery.textScalerOf(context).scale(NiraType.metric) * 9 + 56;
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                first,
                const SizedBox(height: NiraSpace.sm),
                second,
              ],
            )
          : Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: NiraSpace.sm),
                Expanded(child: second),
              ],
            );
    },
  );
}
