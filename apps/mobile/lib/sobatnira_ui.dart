import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const niraGreen = Color(0xFF174B35);
const niraLeaf = Color(0xFF4A7160);
const niraGold = Color(0xFFD3A734);
const niraYellow = Color(0xFFFACA4D);
const niraOchre = Color(0xFFB97105);
const niraPaper = Color(0xFFFEFDF9);
const niraMuted = Color(0xFFB1BFC2);
const niraLine = Color(0xFFD8DEDB);
const niraInset = 30.0;
const niraPanelWidth = 314.0;
const niraShadow = BoxShadow(
  color: Color(0x40000000),
  blurRadius: 6,
  offset: Offset(0, 4),
);

TextStyle niraText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = niraGreen,
  double height = 1.15,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

void showUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Belum tersedia di demo')));
}

class NiraIcon extends StatelessWidget {
  const NiraIcon(this.name, this.size, {this.color, super.key});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/sobatnira/icons/$name.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color,
    excludeFromSemantics: true,
  );
}

enum NiraTab { beranda, kloter, laporan, pengaturan }

class NiraScaffold extends StatelessWidget {
  const NiraScaffold({
    required this.tab,
    required this.onNavigate,
    required this.body,
    this.bottomAction,
    this.actionGap = 14,
    this.floatingNavigation = false,
    super.key,
  });

  final NiraTab tab;
  final ValueChanged<NiraTab> onNavigate;
  final Widget body;
  final Widget? bottomAction;
  final double actionGap;
  final bool floatingNavigation;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    const navigationHeight = 52.0;
    final navigationBottom = math.max(padding.bottom, 16.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: niraPaper,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  SizedBox(height: padding.top + 12),
                  Expanded(child: ClipRect(child: body)),
                  if (!keyboard && bottomAction != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        niraInset,
                        6,
                        niraInset,
                        actionGap,
                      ),
                      child: bottomAction,
                    ),
                  if (!keyboard && !floatingNavigation)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        niraInset,
                        14,
                        niraInset,
                        math.max(padding.bottom, 30),
                      ),
                      child: _BottomNavigation(
                        tab: tab,
                        onNavigate: onNavigate,
                      ),
                    ),
                ],
              ),
              if (!keyboard && floatingNavigation)
                Positioned(
                  left: niraInset,
                  right: niraInset,
                  bottom: navigationBottom,
                  height: navigationHeight,
                  child: _BottomNavigation(tab: tab, onNavigate: onNavigate),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.tab, required this.onNavigate});

  final NiraTab tab;
  final ValueChanged<NiraTab> onNavigate;

  static const _items = [
    (NiraTab.beranda, 'Beranda', 'home', 23.0),
    (NiraTab.kloter, 'Kloter', 'truck', 26.0),
    (NiraTab.laporan, 'Laporan', 'report', 20.0),
    (NiraTab.pengaturan, 'Pengaturan', 'settings', 26.0),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: niraGreen,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 276),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: tab.index.toDouble(),
              end: tab.index.toDouble(),
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            builder: (context, position, _) => LayoutBuilder(
              builder: (context, constraints) {
                final weights = [
                  for (var i = 0; i < _items.length; i++)
                    (1 - (position - i).abs()).clamp(0.0, 1.0),
                ];
                final widths = [
                  for (final w in weights)
                    constraints.maxWidth * (14 + 13 * w) / 69,
                ];
                final starts = <double>[0];
                for (final width in widths) {
                  starts.add(starts.last + width);
                }
                final lower = position.floor();
                final upper = position.ceil();
                final fraction = position - lower;
                final left =
                    starts[lower] + (starts[upper] - starts[lower]) * fraction;
                final width =
                    widths[lower] + (widths[upper] - widths[lower]) * fraction;
                return SizedBox(
                  height: 52,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned(
                        left: left + 2,
                        width: width - 4,
                        top: 10,
                        bottom: 10,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            SizedBox(
                              width: widths[i],
                              child: _destination(i, weights[i]),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _destination(int index, double emphasis) {
    final (item, label, icon, size) = _items[index];
    return Semantics(
      label: label,
      button: true,
      selected: item == tab,
      onTap: () => onNavigate(item),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onNavigate(item),
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NiraIcon(
                  icon,
                  size,
                  color: Color.lerp(Colors.white, niraGreen, emphasis),
                ),
                Flexible(
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: emphasis,
                      child: Opacity(
                        opacity: emphasis,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: niraText(10.5, weight: FontWeight.w700),
                          ),
                        ),
                      ),
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

class NiraTabs extends StatelessWidget {
  const NiraTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.badgeIndex,
    this.badgeCount = 0,
    this.wideIndicator = false,
    this.height = 44,
    this.fontSize = 12,
    this.inset = 22,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final int? badgeIndex;
  final int badgeCount;
  final bool wideIndicator;
  final double height;
  final double fontSize;
  final double inset;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: niraMuted, width: 1)),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(child: _tab(context, index)),
        ],
      ),
    ),
  );

  Widget _tab(BuildContext context, int index) {
    final active = index == selected;
    final showBadge = index == badgeIndex && badgeCount > 0;
    return Semantics(
      button: true,
      selected: active,
      label: showBadge ? '${labels[index]}, $badgeCount kloter' : labels[index],
      onTap: () => onSelected(index),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onSelected(index),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 3,
                  runSpacing: 2,
                  children: [
                    Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: niraText(
                        fontSize,
                        weight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active || MediaQuery.highContrastOf(context)
                            ? niraGreen
                            : niraMuted,
                      ),
                    ),
                    if (showBadge)
                      Container(
                        alignment: Alignment.center,
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: niraGold,
                          shape: BoxShape.circle,
                        ),
                        child: Text('$badgeCount', style: niraText(10)),
                      ),
                  ],
                ),
              ),
              if (active)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: wideIndicator ? 1 : .57,
                      child: Container(height: 2.5, color: niraGreen),
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

class NiraButton extends StatelessWidget {
  const NiraButton(this.label, this.onPressed, {super.key, this.shadow = true});

  final String label;
  final VoidCallback? onPressed;
  final bool shadow;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: niraGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE6EFE5),
        disabledForegroundColor: niraGreen,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        elevation: shadow && onPressed != null ? 3 : 0,
        shadowColor: Colors.black54,
        textStyle: niraText(14.5, weight: FontWeight.w600),
      ),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class NiraOutline extends StatelessWidget {
  const NiraOutline(this.child, {this.color = Colors.white, super.key});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
      side: const BorderSide(color: niraGreen, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
