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
const niraRadius = 8.0;

abstract final class NiraType {
  static const caption = 12.0;
  static const body = 14.0;
  static const section = 16.0;
  static const title = 20.0;
  static const metric = 24.0;
  static const hero = 32.0;
}

abstract final class NiraSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

ThemeData niraTheme() {
  final theme = ThemeData(
    fontFamily: 'Inter',
    useMaterial3: true,
    scaffoldBackgroundColor: niraPaper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: niraGreen,
    ).copyWith(primary: niraGreen, surface: niraPaper),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.copyWith(
      headlineSmall: niraText(NiraType.title, weight: FontWeight.w700),
      titleLarge: niraText(NiraType.section, weight: FontWeight.w600),
      titleMedium: niraText(NiraType.section, weight: FontWeight.w600),
      titleSmall: niraText(NiraType.body, weight: FontWeight.w600),
      bodyLarge: niraText(NiraType.body),
      bodyMedium: niraText(NiraType.body),
      bodySmall: niraText(NiraType.caption, color: niraLeaf),
      labelLarge: niraText(NiraType.body, weight: FontWeight.w600),
      labelMedium: niraText(NiraType.caption, weight: FontWeight.w600),
      labelSmall: niraText(NiraType.caption, weight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: niraPaper,
      foregroundColor: niraGreen,
      titleTextStyle: niraText(NiraType.title, weight: FontWeight.w700),
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(NiraSpace.lg),
      labelStyle: niraText(NiraType.body, color: niraLeaf),
      hintStyle: niraText(NiraType.body, color: niraLeaf),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(niraRadius),
        borderSide: const BorderSide(color: niraLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(niraRadius),
        borderSide: const BorderSide(color: niraLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(niraRadius),
        borderSide: const BorderSide(color: niraGreen, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: niraText(NiraType.body, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(niraRadius),
        ),
      ),
    ),
  );
}

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
  double? height,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height ?? (size >= NiraType.title ? 1.2 : 1.4),
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
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: floatingNavigation && !keyboard
                            ? navigationHeight + navigationBottom + NiraSpace.md
                            : 0,
                      ),
                      child: ClipRect(child: RepaintBoundary(child: body)),
                    ),
                  ),
                  if (!keyboard && bottomAction != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        niraInset,
                        NiraSpace.sm,
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
                  child: RepaintBoundary(
                    child: _BottomNavigation(tab: tab, onNavigate: onNavigate),
                  ),
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
      padding: const EdgeInsets.only(right: NiraSpace.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: tab.index.toDouble(),
              end: tab.index.toDouble(),
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            builder: (context, position, _) => LayoutBuilder(
              builder: (context, constraints) {
                final weights = [
                  for (var i = 0; i < _items.length; i++)
                    (1 - (position - i).abs()).clamp(0.0, 1.0),
                ];
                final widths = [
                  for (final w in weights)
                    constraints.maxWidth *
                        (14 + 13 * w) /
                        (14 * _items.length + 13),
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
            padding: const EdgeInsets.symmetric(horizontal: NiraSpace.xs),
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
                          padding: const EdgeInsets.only(left: NiraSpace.xs),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: niraText(
                              NiraType.caption,
                              weight: FontWeight.w700,
                            ),
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
    this.height = 48,
    this.fontSize = NiraType.body,
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
      child: Stack(
        children: [
          Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(child: _tab(context, index)),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedAlign(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(
                  labels.length == 1
                      ? 0
                      : (2 * (selected + .5) / labels.length - 1) /
                            (1 - (wideIndicator ? 1 : .57) / labels.length),
                  1,
                ),
                child: FractionallySizedBox(
                  widthFactor: (wideIndicator ? 1 : .57) / labels.length,
                  child: const SizedBox(
                    height: 2.5,
                    child: ColoredBox(color: niraGreen),
                  ),
                ),
              ),
            ),
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: NiraSpace.xs,
                  vertical: NiraSpace.sm,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 3,
                  runSpacing: 2,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 320),
                      curve: Curves.easeInOutCubic,
                      style: niraText(
                        fontSize,
                        weight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active || MediaQuery.highContrastOf(context)
                            ? niraGreen
                            : niraMuted,
                      ),
                      child: Text(labels[index], textAlign: TextAlign.center),
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
                        child: Text(
                          '$badgeCount',
                          style: niraText(NiraType.caption),
                        ),
                      ),
                  ],
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
        padding: const EdgeInsets.symmetric(
          vertical: NiraSpace.md,
          horizontal: NiraSpace.lg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(niraRadius),
        ),
        elevation: shadow && onPressed != null ? 3 : 0,
        shadowColor: Colors.black54,
        textStyle: niraText(NiraType.body, weight: FontWeight.w600),
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
      borderRadius: BorderRadius.circular(niraRadius),
      side: const BorderSide(color: niraGreen, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
