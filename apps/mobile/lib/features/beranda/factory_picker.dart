import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';

class FactoryPicker extends StatefulWidget {
  const FactoryPicker({
    required this.value,
    required this.onChanged,
    this.options = const {
      'Pabrik A': 'Pabrik A',
      'Pabrik B': 'Pabrik B',
      'Pabrik C': 'Pabrik C',
    },
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, String> options;

  @override
  State<FactoryPicker> createState() => _FactoryPickerState();
}

class _FactoryPickerState extends State<FactoryPicker> {
  final _anchor = GlobalKey();
  bool _open = false;

  Future<void> _showMenu() async {
    if (_open) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final origin = overlay.globalToLocal(button.localToGlobal(Offset.zero));
    final anchor = origin & button.size;
    final factories = widget.options.keys;
    final choices = [
      if (factories.contains(widget.value)) widget.value,
      for (final factory in factories)
        if (factory != widget.value) factory,
    ];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() => _open = true);
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tutup pilihan pabrik',
      barrierColor: Colors.transparent,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 170),
      pageBuilder: (menuContext, _, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(154.0, constraints.maxWidth - 16);
          final left = (anchor.right - width).clamp(
            8.0,
            math.max(8.0, constraints.maxWidth - width - 8),
          );
          final top = (anchor.bottom + 6).clamp(
            8.0,
            math.max(8.0, constraints.maxHeight - 148),
          );
          return Stack(
            children: [
              Positioned(
                left: left.toDouble(),
                top: top.toDouble(),
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(0, constraints.maxHeight - top - 8),
                  ),
                  child: Material(
                    color: niraPaper,
                    elevation: 4,
                    shadowColor: const Color(0x33174B35),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(niraRadius),
                      side: const BorderSide(color: niraGreen, width: 1.2),
                    ),
                    child: FocusTraversalGroup(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < choices.length; i++) ...[
                              _option(
                                menuContext,
                                choices[i],
                                autofocus: i == 0,
                              ),
                              if (i < choices.length - 1)
                                const Divider(height: 1, color: niraLine),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      transitionBuilder: (context, animation, _, child) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(animation.value);
          return Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, -6 * (1 - progress)),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (selected != null) widget.onChanged(selected);
  }

  Widget _option(
    BuildContext context,
    String factory, {
    required bool autofocus,
  }) {
    final selected = widget.value == factory;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? niraGreen : niraPaper,
        child: InkWell(
          autofocus: autofocus,
          onTap: () => Navigator.of(context).pop(factory),
          hoverColor: selected
              ? const Color(0x24FFFFFF)
              : const Color(0x1F174B35),
          focusColor: selected
              ? const Color(0x24FFFFFF)
              : const Color(0x1F174B35),
          splashColor: const Color(0x33174B35),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiraSpace.md,
                vertical: NiraSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.options[factory]!,
                      style: niraText(
                        NiraType.caption,
                        color: selected ? Colors.white : niraGreen,
                        weight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    key: _anchor,
    color: Colors.white,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: 'Pilih pabrik',
      onPressed: _showMenu,
      color: niraGreen,
      icon: AnimatedRotation(
        turns: _open ? .5 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 170),
        child: const Icon(Icons.keyboard_arrow_down),
      ),
    ),
  );
}
