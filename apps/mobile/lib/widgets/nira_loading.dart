import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';
import 'cane_motif.dart';

class NiraLoading extends StatefulWidget {
  const NiraLoading({
    this.label = 'Memuat data…',
    this.compact = false,
    this.busy = true,
    this.finish = true,
    this.child = const SizedBox.shrink(),
    this.loadingBuilder,
    super.key,
  });

  final String label;
  final bool compact, busy, finish;
  final Widget child;
  final Widget Function(BuildContext, Widget)? loadingBuilder;

  @override
  State<NiraLoading> createState() => _NiraLoadingState();
}

class _NiraLoadingState extends State<NiraLoading>
    with SingleTickerProviderStateMixin {
  static const _waitingLevel = .86;
  late final _fill = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion || !widget.busy) {
      _fill.stop();
    } else if (!_fill.isAnimating && _fill.value < _waitingLevel) {
      _start();
    }
  }

  void _start() => _fill.animateTo(
    _waitingLevel,
    duration: const Duration(seconds: 6),
    curve: Curves.easeOutQuart,
  );

  @override
  void didUpdateWidget(NiraLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy == widget.busy) return;
    if (widget.busy) {
      _fill.value = 0;
      if (!MediaQuery.disableAnimationsOf(context)) _start();
    } else if (widget.finish &&
        _fill.value >= .08 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _fill.animateTo(1, duration: const Duration(milliseconds: 180));
    } else {
      _fill.value = 1;
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) {
        if (!widget.busy &&
            (reducedMotion || !widget.finish || !_fill.isAnimating)) {
          return widget.child;
        }
        final indicator = Center(
          child: Semantics(
            liveRegion: true,
            label: widget.label,
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.all(
                widget.compact ? NiraSpace.xs : NiraSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: Size.square(widget.compact ? 32 : 80),
                    painter: _CaneFillPainter(reducedMotion ? .5 : _fill.value),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(height: NiraSpace.sm),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: niraText(NiraType.body, color: niraLeaf),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
        return widget.loadingBuilder?.call(context, indicator) ?? indicator;
      },
    );
  }
}

class _CaneFillPainter extends CustomPainter {
  const _CaneFillPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32);
    canvas.translate(10, 7);
    final shape = CaneMotif.silhouette;
    final bounds = shape.getBounds();
    canvas.drawPath(shape, Paint()..color = const Color(0xFFDCE9E0));
    final surface = bounds.bottom - bounds.height * progress;
    final amplitude = .85 * math.sin(math.pi * progress);
    final wave = Path()..moveTo(bounds.left, surface);
    for (var x = bounds.left; x <= bounds.right; x += .5) {
      wave.lineTo(x, surface + amplitude * math.sin(x * .32 - progress * 11));
    }
    wave
      ..lineTo(bounds.right, surface)
      ..lineTo(bounds.right, bounds.bottom)
      ..lineTo(bounds.left, bounds.bottom)
      ..close();
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
      wave,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [niraGreen, Color(0xFF479B72)],
        ).createShader(bounds),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = niraLeaf
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CaneFillPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
