import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../../widgets/adaptive_value.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_card.dart';
import 'quick_action_icon.dart';
import 'factory_picker.dart';

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    required this.kloter,
    required this.onOpenKloter,
    this.onQuickAction,
    this.factoryId,
    this.factories = const {},
    this.onFactoryChanged,
    this.profile,
    this.summary,
    this.profit,
    this.period,
    this.onPeriod,
    this.reportStatus,
    this.statusMessage,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;
  final ValueChanged<QuickActionKind>? onQuickAction;
  final String? factoryId;
  final Map<String, String> factories;
  final ValueChanged<String>? onFactoryChanged;
  final String? profile;
  final ({String cane, String lots})? summary;
  final Widget? statusMessage;
  final Widget? reportStatus;
  final String? profit, period;
  final VoidCallback? onPeriod;

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
    final showEmpty = items.isEmpty && widget.statusMessage == null;
    return LayoutBuilder(
      builder: (context, constraints) {
        _measureHeader();
        final height = constraints.maxHeight;
        final inset = niraPageInset(context);
        final header = _header(inset);
        final headerHeight = _headerHeight ?? 440;
        if (height - headerHeight < 160 || headerHeight > height * .78) {
          return CustomScrollView(
            key: const PageStorageKey('beranda-compact-scroll'),
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(child: _tabs()),
              if (widget.statusMessage case final status?)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: status,
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  inset,
                  NiraSpace.md,
                  inset,
                  NiraSpace.lg,
                ),
                sliver: SliverList.builder(
                  itemCount: showEmpty ? 1 : items.length,
                  itemBuilder: (context, index) =>
                      showEmpty ? _emptyList() : _card(items[index]),
                ),
              ),
            ],
          );
        }
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
                child: header,
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
                    Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        _tabs(scrollController),
                        Semantics(
                          label: 'Tarik daftar kloter ke atas',
                          button: true,
                          child: GestureDetector(
                            key: const ValueKey('beranda-kloter-handle'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (!_sheet.isAttached) return;
                              _sheet.animateTo(
                                _sheet.size < expanded - .01
                                    ? expanded
                                    : collapsed,
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
                              height: 20,
                              width: 48,
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
                      ],
                    ),
                    if (widget.statusMessage case final status?)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        child: status,
                      ),
                    Expanded(
                      child: ListView.builder(
                        key: const ValueKey('beranda-kloter-list'),
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          inset,
                          NiraSpace.md,
                          inset,
                          NiraSpace.lg,
                        ),
                        itemCount: showEmpty ? 1 : items.length,
                        itemBuilder: (context, index) =>
                            showEmpty ? _emptyList() : _card(items[index]),
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

  Widget _header(double inset) => CustomPaint(
    key: _headerKey,
    painter: const _BerandaGeometryPainter(),
    child: Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, NiraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Profile(
            factoryId: widget.factoryId,
            factories: widget.factories,
            onFactoryChanged: widget.onFactoryChanged,
            profile: widget.profile,
          ),
          const SizedBox(height: NiraSpace.lg),
          _ProductionSummary(
            summary: widget.summary,
            profit: widget.profit,
            period: widget.period,
            onPeriod: widget.onPeriod,
          ),
          if (widget.reportStatus != null) widget.reportStatus!,
          const SizedBox(height: NiraSpace.md),
          _QuickActions(onSelected: widget.onQuickAction),
        ],
      ),
    ),
  );

  Widget _tabs([ScrollController? controller]) => NiraTabs(
    labels: const ['Tinjau', 'Tuntas'],
    selected: _selected,
    inset: 27,
    wideIndicator: true,
    onSelected: (value) {
      if (controller != null && controller.hasClients) controller.jumpTo(0);
      setState(() => _selected = value);
    },
  );

  Widget _card(DemoKloter item) => Padding(
    padding: const EdgeInsets.only(bottom: NiraSpace.sm),
    child: KloterCard(kloter: item, onTap: () => widget.onOpenKloter(item)),
  );
  Widget _emptyList() => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.lg),
    child: Text(
      widget.kloter.isEmpty
          ? 'Belum ada kloter di pabrik ini.'
          : _selected == 0
          ? 'Tidak ada kloter yang perlu ditinjau.'
          : 'Belum ada kloter tuntas.',
      textAlign: TextAlign.center,
      style: niraText(NiraType.body, color: niraLeaf),
    ),
  );
}

class _Profile extends StatefulWidget {
  const _Profile({
    this.factoryId,
    required this.factories,
    this.onFactoryChanged,
    this.profile,
  });

  final String? factoryId;
  final Map<String, String> factories;
  final ValueChanged<String>? onFactoryChanged;
  final String? profile;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  String _factory = 'Pabrik A';
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
                widget.factories[widget.factoryId] ?? _factory,
                style: niraText(NiraType.caption, color: Colors.white),
              ),
              const SizedBox(height: 1),
              Text(
                widget.profile ?? 'Admin Demo',
                style: niraText(
                  NiraType.section,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (widget.factoryId == null)
          FactoryPicker(
            value: _factory,
            onChanged: (value) => setState(() => _factory = value),
          )
        else if (widget.factories.length > 1)
          FactoryPicker(
            value: widget.factoryId!,
            options: widget.factories,
            onChanged: widget.onFactoryChanged!,
          ),
      ],
    ),
  );
}

class _ProductionSummary extends StatefulWidget {
  const _ProductionSummary({
    this.summary,
    this.profit,
    this.period,
    this.onPeriod,
  });
  final String? profit, period;
  final VoidCallback? onPeriod;
  final ({String cane, String lots})? summary;

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
                          child: NiraValue(
                            _showProfit ? (widget.profit ?? '—') : 'Rp ••••••',
                            label: 'Keuntungan',
                            style: niraText(
                              NiraType.hero,
                              color: niraYellow,
                              weight: FontWeight.w700,
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
                    InkWell(
                      onTap: widget.onPeriod,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: NiraSpace.sm),
                            Expanded(
                              child: Text(
                                widget.period ??
                                    'Semua tanggal · data sintetis',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: niraText(
                                  NiraType.caption,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (widget.onPeriod != null)
                              const Icon(
                                Icons.expand_more,
                                color: Colors.white,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NiraSpace.md),
        NiraSummaryPair(
          first: NiraSummaryCard(
            'Tebu diterima',
            widget.summary?.cane ?? '—',
            boxes: true,
          ),
          second: NiraSummaryCard('Jumlah kloter', widget.summary?.lots ?? '—'),
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
