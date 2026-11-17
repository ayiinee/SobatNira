import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_card.dart';
import 'quick_action_icon.dart';
import 'factory_picker.dart';

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    required this.kloter,
    required this.onOpenKloter,
    this.onQuickAction,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;
  final ValueChanged<QuickActionKind>? onQuickAction;

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  int _selected = 0;
  final _headerKey = GlobalKey();
  final _sheet = DraggableScrollableController();
  double? _headerHeight;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _measureHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          (_headerHeight == null ||
              (box.size.height - _headerHeight!).abs() > .5)) {
        setState(() => _headerHeight = box.size.height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _selected == 0 ? KloterStatus.review : KloterStatus.done;
    final items = widget.kloter.where((item) => item.status == status).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        _measureHeader();
        final height = constraints.maxHeight;
        final headerHeight = (_headerHeight ?? 440).clamp(0.0, height * .72);
        final collapsed = (1 - headerHeight / height).clamp(.22, .75);
        final expanded = (collapsed + .22).clamp(collapsed, .94);
        void settle() {
          if (!_sheet.isAttached) return;
          final target = _sheet.size > (collapsed + expanded) / 2
              ? expanded
              : collapsed;
          _sheet.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }

        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: headerHeight,
              child: SingleChildScrollView(
                key: const PageStorageKey('beranda-fixed-header'),
                child: CustomPaint(
                  key: _headerKey,
                  painter: const _BerandaGeometryPainter(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      niraInset,
                      0,
                      niraInset,
                      NiraSpace.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Profile(),
                        const SizedBox(height: NiraSpace.lg),
                        const _ProductionSummary(),
                        const SizedBox(height: NiraSpace.lg),
                        _QuickActions(onSelected: widget.onQuickAction),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: collapsed,
              minChildSize: collapsed,
              maxChildSize: expanded,
              snap: true,
              builder: (context, scrollController) => Material(
                color: niraPaper,
                clipBehavior: Clip.antiAlias,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  side: BorderSide(color: niraLeaf),
                ),
                child: Column(
                  children: [
                    Semantics(
                      label: 'Tarik daftar kloter ke atas',
                      button: true,
                      child: GestureDetector(
                        key: const ValueKey('beranda-kloter-handle'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_sheet.isAttached) return;
                          _sheet.animateTo(
                            _sheet.size < expanded - .01 ? expanded : collapsed,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        onVerticalDragUpdate: (event) {
                          if (_sheet.isAttached) {
                            _sheet.jumpTo(
                              (_sheet.size - event.delta.dy / height).clamp(
                                collapsed,
                                expanded,
                              ),
                            );
                          }
                        },
                        onVerticalDragEnd: (_) => settle(),
                        child: SizedBox(
                          height: 24,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: niraMuted,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    NiraTabs(
                      labels: const ['Tinjau', 'Tuntas'],
                      selected: _selected,
                      height: 48,
                      fontSize: NiraType.body,
                      inset: 27,
                      wideIndicator: true,
                      onSelected: (value) {
                        if (scrollController.hasClients) {
                          scrollController.jumpTo(0);
                        }
                        setState(() => _selected = value);
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const ValueKey('beranda-kloter-list'),
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          niraInset,
                          NiraSpace.md,
                          niraInset,
                          NiraSpace.lg,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: NiraSpace.sm),
                          child: KloterCard(
                            kloter: items[index],
                            onTap: () => widget.onOpenKloter(items[index]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
    padding: const EdgeInsets.symmetric(
      horizontal: NiraSpace.md,
      vertical: NiraSpace.sm,
    ),
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
        const SizedBox(width: NiraSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _factory,
                style: niraText(NiraType.caption, color: Colors.white),
              ),
              const SizedBox(height: 1),
              Text(
                'Admin Demo',
                style: niraText(
                  NiraType.section,
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
    padding: const EdgeInsets.fromLTRB(
      NiraSpace.sm,
      NiraSpace.sm,
      NiraSpace.sm,
      NiraSpace.lg,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: niraGreen, width: 1.35),
      borderRadius: BorderRadius.circular(niraRadius),
      boxShadow: const [niraShadow],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: niraGreen,
            borderRadius: BorderRadius.circular(niraRadius),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NiraSpace.lg,
                  NiraSpace.sm,
                  NiraSpace.md,
                  NiraSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keuntungan',
                      style: niraText(
                        NiraType.section,
                        color: Colors.white,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: NiraSpace.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _showProfit ? 'Rp15.745.000' : 'Rp ••••••',
                              style: niraText(
                                NiraType.hero,
                                color: niraYellow,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: NiraSpace.xs),
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
                    const SizedBox(height: NiraSpace.sm),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: NiraSpace.sm),
                        Flexible(
                          child: Text(
                            '20 Oktober 2026',
                            style: niraText(
                              NiraType.caption,
                              color: Colors.white,
                            ),
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
        const SizedBox(height: NiraSpace.md),
        const NiraSummaryPair(
          first: NiraSummaryCard('Tebu diterima', '8.200Kg', boxes: true),
          second: NiraSummaryCard('Jumlah kloter', '3'),
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
      ..color = const Color(0x08D6E9DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final leaf = Paint()..color = const Color(0x08D6E9DB);
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
      ..strokeWidth = 2.25
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Flowing contours frame the cards without adding animation work.
    for (var i = 0; i < 5; i++) {
      final step = i * 19.0;
      canvas.drawPath(
        Path()
          ..moveTo(size.width + 30, 12 + step)
          ..cubicTo(
            size.width * .55 - step,
            55 + step,
            size.width * .62 - step,
            165 + step,
            size.width + 30,
            240 + step,
          ),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-25, size.height - 245 + step)
          ..cubicTo(
            size.width * .52 + step,
            size.height - 210 + step,
            size.width * .42 + step,
            size.height - 65 + step,
            -25,
            size.height + 22 + step,
          ),
        pen,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BerandaGeometryPainter oldDelegate) => false;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({this.onSelected});
  final ValueChanged<QuickActionKind>? onSelected;

  static const _actions = [
    ('Laba', QuickActionKind.profit),
    ('Rekap', QuickActionKind.recap),
    ('Biaya Ops', QuickActionKind.expenses),
    ('Bantuan', QuickActionKind.help),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              MediaQuery.textScalerOf(context).scale(NiraType.caption) * 24
          ? 4
          : 2;
      final width =
          (constraints.maxWidth - NiraSpace.md * (columns - 1)) / columns;
      return Wrap(
        spacing: NiraSpace.md,
        runSpacing: NiraSpace.lg,
        children: [
          for (final (label, icon) in _actions)
            SizedBox(
              width: width,
              child: _QuickActionTile(
                label: label,
                icon: icon,
                onTap: () => onSelected == null
                    ? showUnavailable(context)
                    : onSelected!(icon),
              ),
            ),
        ],
      );
    },
  );
}

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final QuickActionKind icon;
  final VoidCallback onTap;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final animate = active && !reduceMotion;
    final tilt = switch (widget.icon) {
      QuickActionKind.profit || QuickActionKind.recap => -.014,
      QuickActionKind.expenses || QuickActionKind.help => .014,
    };

    return Semantics(
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        borderRadius: BorderRadius.circular(niraRadius),
        child: Column(
          children: [
            AnimatedSlide(
              offset: animate && !_pressed
                  ? const Offset(0, -.06)
                  : Offset.zero,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                height: 64,
                width: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFF4F8F1) : Colors.white,
                  borderRadius: BorderRadius.circular(niraRadius),
                  border: Border.all(color: niraGreen, width: 1.3),
                ),
                child: AnimatedScale(
                  scale: reduceMotion
                      ? 1
                      : (_pressed ? .95 : (active ? 1.1 : 1)),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedRotation(
                    turns: animate && !_pressed ? tilt : 0,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: QuickActionIcon(widget.icon),
                  ),
                ),
              ),
            ),
            const SizedBox(height: NiraSpace.xs),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: niraText(
                NiraType.caption,
                color: Colors.black,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
