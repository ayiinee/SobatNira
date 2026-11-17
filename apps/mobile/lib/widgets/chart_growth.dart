import 'package:flutter/material.dart';

/// Keeps chart axes stationary while the plotted values grow from the baseline.
class ChartGrowth extends StatelessWidget {
  const ChartGrowth({required this.builder, this.replayKey, super.key});

  final Widget Function(BuildContext context, double progress) builder;
  final Object? replayKey;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(replayKey),
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1100),
    curve: Curves.easeInOutCubic,
    builder: (context, progress, _) => builder(context, progress),
  );
}
