import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_card.dart';
import 'quick_action_icon.dart';
import 'factory_picker.dart';

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    required this.kloter,
    required this.onOpenKloter,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final status = _selected == 0 ? KloterStatus.review : KloterStatus.done;
    final recent = widget.kloter.where((item) => item.status == status).take(3);
    return CustomScrollView(
      key: const PageStorageKey('beranda-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: CustomPaint(
            painter: const _BerandaGeometryPainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(niraInset, 0, niraInset, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _Profile(),
                  SizedBox(height: 15),
                  _ProductionSummary(),
                  SizedBox(height: 17),
                  _QuickActions(),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 82,
          ),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: niraLeaf, width: 1),
                  left: BorderSide(color: niraLeaf, width: 1),
                  right: BorderSide(color: niraLeaf, width: 1),
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NiraTabs(
                    labels: const ['Tinjau', 'Tuntas'],
                    selected: _selected,
                    height: 50,
                    fontSize: 14.5,
                    inset: 27,
                    wideIndicator: true,
                    onSelected: (value) => setState(() => _selected = value),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      niraInset,
                      15,
                      niraInset,
                      13,
                    ),
                    child: Column(
                      children: [
                        for (final item in recent)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: KloterCard(
                              kloter: item,
                              onTap: () => widget.onOpenKloter(item),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 82),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  String _factory = 'Pabrik Demo';
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 57),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(33),
      border: Border.all(color: niraGreen, width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18174B35),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        ClipOval(
          child: Image.asset(
            'assets/sobatnira/art/profil-demo.png',
            width: 40,
            height: 40,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_factory, style: niraText(10.5, color: Colors.white)),
              const SizedBox(height: 1),
              Text(
                'Admin Demo',
                style: niraText(
                  16,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        FactoryPicker(
          value: _factory,
          onChanged: (value) => setState(() => _factory = value),
        ),
      ],
    ),
  );
}

class _ProductionSummary extends StatefulWidget {
  const _ProductionSummary();

  @override
  State<_ProductionSummary> createState() => _ProductionSummaryState();
}

class _ProductionSummaryState extends State<_ProductionSummary> {
  bool _showProfit = true;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(9, 9, 9, 15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: niraGreen, width: 1.35),
      borderRadius: BorderRadius.circular(9),
      boxShadow: const [niraShadow],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: niraGreen,
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B231A), Color(0xFF287653), niraGreen],
              stops: [0, .6, 1],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _CanePatternPainter()),
                  ),
                ),
              ),
              Positioned(
                right: -9,
                bottom: 0,
                top: 0,
                width: 153,
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/sobatnira/art/hero-cane.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                    opacity: const AlwaysStoppedAnimation(.9),
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 9, 12, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Keuntungan',
                            style: niraText(
                              17,
                              color: Colors.white,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              setState(() => _showProfit = !_showProfit),
                          tooltip: _showProfit
                              ? 'Sembunyikan keuntungan'
                              : 'Tampilkan keuntungan',
                          isSelected: !_showProfit,
                          icon: Icon(
                            _showProfit
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 21,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _showProfit ? 'Rp -' : 'Rp ••••••',
                      style: niraText(
                        33,
                        color: niraYellow,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '20 Oktober 2026',
                            style: niraText(11.8, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SummaryTile('Tebu diterima', '8.200Kg', cane: true),
            ),
            SizedBox(width: 9),
            Expanded(child: _SummaryTile('Jumlah kloter', '3')),
          ],
        ),
      ],
    ),
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value, {this.cane = false});

  final String label;
  final String value;
  final bool cane;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B231A), Color(0xFF205D42), niraGreen],
        stops: [0, .6, 1],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          bottom: -12,
          right: -8,
          child: IgnorePointer(
            child: cane
                ? Image.asset(
                    'assets/sobatnira/art/cane.png',
                    width: 110,
                    height: 100,
                    fit: BoxFit.cover,
                    color: const Color(0x20FFFFFF),
                    excludeFromSemantics: true,
                  )
                : const Icon(
                    Icons.layers_outlined,
                    color: Color(0x20FFFFFF),
                    size: 100,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: niraText(
                    12,
                    color: Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: niraText(
                    23,
                    color: niraYellow,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// Decorative sugarcane motif; independent of data and layout measurements.
class _CanePatternPainter extends CustomPainter {
  const _CanePatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = const Color(0x12D6E9DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final leaf = Paint()..color = const Color(0x12D6E9DB);
    for (var row = 0; row * 29 < size.height + 29; row++) {
      for (var col = 0; col * 28 < size.width + 28; col++) {
        canvas.save();
        canvas.translate(col * 28 + (row.isOdd ? 14 : 0), row * 29.0);
        canvas.rotate(.35);
        for (var stalk = 0; stalk < 2; stalk++) {
          for (var joint = 0; joint < 3; joint++) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(stalk * 7.0, joint * 7.0, 5, 6),
                const Radius.circular(1.3),
              ),
              outline,
            );
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(6, 7)
            ..quadraticBezierTo(-6, 7, -5, -1)
            ..quadraticBezierTo(3, -1, 6, 7)
            ..close(),
          leaf,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7, 7)
            ..quadraticBezierTo(7, -5, 17, -4)
            ..quadraticBezierTo(17, 4, 7, 7)
            ..close(),
          leaf,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanePatternPainter oldDelegate) => false;
}

class _BerandaGeometryPainter extends CustomPainter {
  const _BerandaGeometryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0x30B97105)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Two quiet clusters of open, parallel contours frame the content.
    for (var i = 0; i < 5; i++) {
      final step = i * 19.0;
      canvas.drawPath(
        Path()
          ..moveTo(size.width + 30, 12 + step)
          ..lineTo(size.width * .68 - step, 112 + step)
          ..lineTo(size.width + 30, 240 + step),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-25, size.height - 245 + step)
          ..lineTo(size.width * .3 + step, size.height - 125 + step)
          ..lineTo(-25, size.height + 22 + step),
        pen,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BerandaGeometryPainter oldDelegate) => false;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = [
    ('Laba', QuickActionKind.profit),
    ('Biaya Ops', QuickActionKind.expenses),
    ('Rekap', QuickActionKind.recap),
    ('Bantuan', QuickActionKind.help),
  ];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (label, icon) in _actions)
        Flexible(
          child: SizedBox(
            width: 63,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => showUnavailable(context),
                borderRadius: BorderRadius.circular(7),
                child: Column(
                  children: [
                    Container(
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: niraGreen, width: 1.3),
                      ),
                      child: QuickActionIcon(icon),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: niraText(
                        11.5,
                        color: Colors.black,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
