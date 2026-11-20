import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets/nira_loading.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const niraGreen = Color(0xFF174B35);
const niraGreenHover = Color(0xFF2B624B);
final niraGreenOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
  if (states.contains(WidgetState.disabled)) return null;
  if (states.contains(WidgetState.pressed)) return const Color(0x24FFFFFF);
  if (states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused)) {
    return const Color(0x18FFFFFF);
  }
  return null;
});
const niraLeaf = Color(0xFF4A7160);
const niraGold = Color(0xFFD3A734);
const niraYellow = Color(0xFFFACA4D);
const niraOchre = Color(0xFFB97105);
const niraPaper = Color(0xFFFEFDF9);
const niraMuted = Color(0xFFB1BFC2);
const niraLine = Color(0xFFD8DEDB);
const niraRadius = 8.0;
const niraMaxContentWidth = 600.0;

double niraPageInset(BuildContext context) {
  final width =
      MediaQuery.sizeOf(context).width -
      MediaQuery.viewPaddingOf(context).horizontal;
  return (16 + (width - 320) * .2).clamp(16.0, 30.0);
}

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
      ).copyWith(overlayColor: niraGreenOverlay),
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
    this.extendBehindNavigation = false,
    this.topGap = 12,
    this.hideNavigationWhileEditing = false,
    super.key,
  });

  final NiraTab tab;
  final ValueChanged<NiraTab> onNavigate;
  final Widget body;
  final Widget? bottomAction;
  final double actionGap;
  final bool floatingNavigation;
  final bool extendBehindNavigation;
  final double topGap;
  final bool hideNavigationWhileEditing;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FocusManager.instance,
    builder: (context, _) => _buildLayout(context),
  );

  Widget _buildLayout(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editing =
        hideNavigationWhileEditing &&
        focusContext != null &&
        focusContext.mounted &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorStateOfType<EditableTextState>() != null);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideNavigation = keyboard || (hideNavigationWhileEditing && editing);
    final inset = niraPageInset(context);
    final navigationInset = inset + 6;
    final short = MediaQuery.sizeOf(context).height - padding.vertical < 500;
    const navigationHeight = _BottomNavigation.height;
    final navigationBottom =
        math.max(padding.bottom, short ? 4.0 : 16.0) + (short ? 4 : 8);
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
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: niraMaxContentWidth),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      SizedBox(
                        height:
                            padding.top +
                            (short ? math.min(topGap, 4) : topGap),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                floatingNavigation &&
                                    !hideNavigation &&
                                    !extendBehindNavigation
                                ? navigationHeight +
                                      navigationBottom +
                                      NiraSpace.md
                                : hideNavigation && !keyboard
                                ? padding.bottom
                                : 0,
                          ),
                          child: ClipRect(child: RepaintBoundary(child: body)),
                        ),
                      ),
                      if (!keyboard && bottomAction != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            inset,
                            NiraSpace.sm,
                            inset,
                            short
                                ? math.min(actionGap, NiraSpace.sm)
                                : actionGap,
                          ),
                          child: bottomAction,
                        ),
                      if (!hideNavigation && !floatingNavigation)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            navigationInset,
                            short ? 4 : 14,
                            navigationInset,
                            math.max(navigationBottom, short ? 8.0 : 38.0),
                          ),
                          child: _BottomNavigation(
                            tab: tab,
                            onNavigate: onNavigate,
                          ),
                        ),
                    ],
                  ),
                  if (!hideNavigation && floatingNavigation)
                    Positioned(
                      left: navigationInset,
                      right: navigationInset,
                      bottom: navigationBottom,
                      height: navigationHeight,
                      child: RepaintBoundary(
                        child: _BottomNavigation(
                          tab: tab,
                          onNavigate: onNavigate,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.tab, required this.onNavigate});

  static const height = 52.0;
  final NiraTab tab;
  final ValueChanged<NiraTab> onNavigate;

  static const _items = [
    (NiraTab.beranda, 'Beranda', 'home', 23.0),
    (NiraTab.kloter, 'Kloter', 'truck', 26.0),
    (NiraTab.laporan, 'Laporan', 'report', 20.0),
    (NiraTab.pengaturan, 'Pengaturan', 'settings', 26.0),
  ];

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: niraGreen,
        borderRadius: BorderRadius.circular(height / 2),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final style = niraText(12, weight: FontWeight.w600, height: 1.15);
              final activeWidths = [
                for (final (_, label, _, iconSize) in _items)
                  (() {
                    final painter = TextPainter(
                      text: TextSpan(text: label, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final width = painter.width + iconSize + 28;
                    painter.dispose();
                    return width;
                  })(),
              ];
              const targetWidth = 48.0;
              final requiredWidth =
                  activeWidths.reduce(math.max) +
                  targetWidth * (_items.length - 1);
              final showLabel = constraints.maxWidth >= requiredWidth;
              final desiredInset = (constraints.maxWidth * .09).clamp(
                8.0,
                36.0,
              );
              final inset = showLabel
                  ? math.min(
                      desiredInset,
                      (constraints.maxWidth - requiredWidth) / 2,
                    )
                  : math.min(
                      desiredInset,
                      math.max(
                        0.0,
                        (constraints.maxWidth - targetWidth * _items.length) /
                            2,
                      ),
                    );
              final available = constraints.maxWidth - inset * 2;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: tab.index.toDouble(),
                    end: tab.index.toDouble(),
                  ),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  builder: (context, position, _) {
                    final lower = position.floor();
                    final upper = position.ceil();
                    final fraction = position - lower;
                    final activeWidth = showLabel
                        ? activeWidths[lower] +
                              (activeWidths[upper] - activeWidths[lower]) *
                                  fraction
                        : available / _items.length;
                    final idleWidth =
                        (available - activeWidth) / (_items.length - 1);
                    final weights = [
                      for (var i = 0; i < _items.length; i++)
                        (1 - (position - i).abs()).clamp(0.0, 1.0),
                    ];
                    final widths = [
                      for (final weight in weights)
                        idleWidth + (activeWidth - idleWidth) * weight,
                    ];
                    final starts = <double>[0];
                    for (final width in widths) {
                      starts.add(starts.last + width);
                    }
                    final left =
                        starts[lower] +
                        (starts[upper] - starts[lower]) * fraction;
                    final width =
                        widths[lower] +
                        (widths[upper] - widths[lower]) * fraction;
                    return Stack(
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
                              borderRadius: BorderRadius.all(
                                Radius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _items.length; i++)
                              SizedBox(
                                width: widths[i],
                                child: _destination(
                                  i,
                                  weights[i],
                                  style,
                                  showLabel,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _destination(
    int index,
    double emphasis,
    TextStyle style,
    bool showLabel,
  ) {
    final (item, label, icon, size) = _items[index];
    return Semantics(
      label: label,
      button: true,
      selected: item == tab,
      onTap: () => onNavigate(item),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onNavigate(item),
        overlayColor: niraGreenOverlay,
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4 + 6 * emphasis),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NiraIcon(
                  icon,
                  size,
                  color: Color.lerp(Colors.white, niraGreen, emphasis),
                ),
                if (showLabel)
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
                              style: style,
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

  List<int> get _flexes => [
    for (var i = 0; i < labels.length; i++) i == badgeIndex ? 2 : 1,
  ];

  double get _indicatorWidth {
    final flexes = _flexes;
    final total = flexes.fold(0, (sum, flex) => sum + flex);
    return (wideIndicator ? 1 : .57) * flexes[selected] / total;
  }

  double get _indicatorAlignment {
    if (labels.length == 1) return 0;
    final flexes = _flexes;
    final total = flexes.fold(0, (sum, flex) => sum + flex);
    final preceding = flexes.take(selected).fold(0, (sum, flex) => sum + flex);
    final center = (preceding + flexes[selected] / 2) / total;
    return (2 * center - 1) / (1 - _indicatorWidth);
  }

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
                Expanded(flex: _flexes[index], child: _tab(context, index)),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedAlign(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(_indicatorAlignment, 1),
                child: FractionallySizedBox(
                  widthFactor: _indicatorWidth,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: AnimatedDefaultTextStyle(
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
                        child: Text(
                          labels[index],
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (showBadge) ...[
                      const SizedBox(width: NiraSpace.xs),
                      Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: NiraSpace.xs,
                        ),
                        decoration: BoxDecoration(
                          color: niraGold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: niraText(
                            NiraType.caption,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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

class NiraPageHeight {
  double? _width;
  double _height = 0;

  void reset() {
    _width = null;
    _height = 0;
  }
}

class NiraPageBody extends SingleChildRenderObjectWidget {
  const NiraPageBody({
    super.key,
    required this.height,
    required this.firstPage,
    required Widget child,
  }) : super(child: child);

  final NiraPageHeight height;
  final bool firstPage;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PageBodyBox(height, firstPage);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _PageBodyBox;
    box.height = height;
    box.firstPage = firstPage;
    box.markNeedsLayout();
  }
}

class _PageBodyBox extends RenderProxyBox {
  _PageBodyBox(this.height, this.firstPage);

  NiraPageHeight height;
  bool firstPage;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final content = child!.getDryLayout(constraints);
    final reserved = !firstPage && height._width == constraints.maxWidth
        ? height._height
        : 0.0;
    return constraints.constrain(
      Size(content.width, math.max(content.height, reserved)),
    );
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final content = child!.size;
    if (firstPage || height._width != constraints.maxWidth) height.reset();
    height._width = constraints.maxWidth;
    height._height = math.max(content.height, height._height);
    size = constraints.constrain(Size(content.width, height._height));
  }
}

/// Retains the previous page layout while a different page is loading.
class NiraPagedFutureBuilder<T> extends StatefulWidget {
  const NiraPagedFutureBuilder({
    required this.future,
    required this.page,
    required this.builder,
    this.dataset,
    super.key,
  });

  final Future<T>? future;
  final int page;
  final Object? dataset;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<NiraPagedFutureBuilder<T>> createState() =>
      _NiraPagedFutureBuilderState<T>();
}

class _NiraPagedFutureBuilderState<T> extends State<NiraPagedFutureBuilder<T>> {
  Widget? _lastPage;
  bool _changingPage = false;

  @override
  void didUpdateWidget(covariant NiraPagedFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dataset != oldWidget.dataset) _lastPage = null;
    if (widget.future != oldWidget.future) {
      _changingPage = widget.page != oldWidget.page && _lastPage != null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: widget.future,
    builder: (context, snapshot) {
      final waiting = snapshot.connectionState == ConnectionState.waiting;
      final holdingPage = waiting && _changingPage && _lastPage != null;
      final content = holdingPage
          ? _lastPage!
          : widget.builder(context, snapshot);
      if (snapshot.connectionState == ConnectionState.done) {
        _lastPage = snapshot.hasData ? content : null;
      }
      return Stack(
        fit: StackFit.passthrough,
        children: [
          ExcludeFocus(
            excluding: holdingPage,
            child: IgnorePointer(ignoring: holdingPage, child: content),
          ),
          if (holdingPage)
            const Positioned.fill(
              child: IgnorePointer(child: NiraLoading(compact: true)),
            ),
        ],
      );
    },
  );
}

class NiraPagination extends StatelessWidget {
  const NiraPagination({
    required this.page,
    this.pageCount,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final int page;
  final int? pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final totalPages = pageCount;
    final label = totalPages == null
        ? 'Halaman $page'
        : '$page dari $totalPages';
    final showPrevious = page > 1;
    final showNext = totalPages == null ? onNext != null : page < totalPages;
    final arrowStyle = IconButton.styleFrom(
      backgroundColor: niraGreen,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFE6EFE5),
      disabledForegroundColor: niraGreen.withValues(alpha: .45),
      shape: const RoundedRectangleBorder(),
    ).copyWith(overlayColor: niraGreenOverlay);
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: NiraSpace.sm),
        child: Material(
          color: niraPaper,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(niraRadius)),
            side: BorderSide(color: niraLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPrevious) ...[
                IconButton.filled(
                  tooltip: 'Sebelumnya',
                  onPressed: onPrevious,
                  style: arrowStyle,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(
                  height: 24,
                  child: VerticalDivider(width: 1, color: niraLine),
                ),
              ],
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NiraSpace.lg),
                  child: Semantics(
                    liveRegion: true,
                    label: pageCount == null ? label : 'Halaman $label',
                    excludeSemantics: true,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: niraText(NiraType.body, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              if (showNext) ...[
                const SizedBox(
                  height: 24,
                  child: VerticalDivider(width: 1, color: niraLine),
                ),
                IconButton.filled(
                  tooltip: 'Berikutnya',
                  onPressed: onNext,
                  style: arrowStyle,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NiraButton extends StatelessWidget {
  const NiraButton(
    this.label,
    this.onPressed, {
    super.key,
    this.shadow = true,
    this.visualDensity,
    this.minimumHeight = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool shadow;
  final VisualDensity? visualDensity;
  final double minimumHeight;

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
        minimumSize: Size(0, minimumHeight),
        visualDensity: visualDensity,
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
      ).copyWith(overlayColor: niraGreenOverlay),
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
