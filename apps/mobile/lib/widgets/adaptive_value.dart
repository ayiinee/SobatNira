import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';

// Work on displayed decimal strings, preserving the complete API value even
// above JavaScript's safe integer range.
final _number = RegExp(
  r'^(-?)(Rp\s*)?(\d[\d.]*)(?:,(\d+))?(\s*(?:kg|Kg|L|l|mL|ml|%|°Bx|/Kg|/kg))?$',
);

bool isDisplayNumber(String value) => _number.hasMatch(value);

String _unit(RegExpMatch match) {
  final unit = match[5]?.trim() ?? '';
  return unit.isEmpty || unit.startsWith('/') ? unit : ' $unit';
}

String compactDisplayValue(String value, {bool short = false}) {
  final match = _number.firstMatch(value);
  if (match == null) return value;
  final digits = match[3]!
      .replaceAll('.', '')
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.length <= 3) return value;
  final group = ((digits.length - 1) ~/ 3).clamp(1, 4);
  final places = group * 3;
  final whole = digits.substring(0, digits.length - places);
  final fraction = digits
      .substring(digits.length - places)
      .padRight(2, '0')
      .substring(0, 2)
      .replaceFirst(RegExp(r'0+$'), '');
  final suffix = (short
      ? ['rb', 'jt', 'M', 'T']
      : ['ribu', 'juta', 'miliar', 'triliun'])[group - 1];
  return '${match[1]}${match[2]?.trim() ?? ''}$whole${fraction.isEmpty ? '' : ',$fraction'} $suffix${_unit(match)}';
}

String scientificDisplayValue(String value) {
  final match = _number.firstMatch(value);
  if (match == null) return value;
  final digits = match[3]!
      .replaceAll('.', '')
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.length <= 3) return value;
  final fraction = digits
      .substring(1)
      .padRight(2, '0')
      .substring(0, 2)
      .replaceFirst(RegExp(r'0+$'), '');
  return '${match[1]}${match[2]?.trim() ?? ''}${digits[0]}${fraction.isEmpty ? '' : ',$fraction'}e${digits.length - 1}${_unit(match)}';
}

double valueTextHeight(BuildContext context, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: '0', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// One stable line with the complete, selectable value on tap whenever
/// shortened or scrollable. Detail fields can disable abbreviation.
class NiraValue extends StatelessWidget {
  const NiraValue(
    this.value, {
    required this.style,
    this.label,
    this.abbreviate = true,
    this.revealOnTap = true,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final String value;
  final String? label;
  final TextStyle style;
  final bool abbreviate;
  final bool revealOnTap;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: valueTextHeight(context, style),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        bool fits(String text) {
          painter.text = TextSpan(text: text, style: style);
          painter.layout();
          return painter.width <= constraints.maxWidth;
        }

        var display = value;
        if (!fits(display) && abbreviate) {
          for (final candidate in [
            compactDisplayValue(value),
            compactDisplayValue(value, short: true),
            scientificDisplayValue(value),
          ]) {
            display = candidate;
            if (fits(candidate)) break;
          }
        }
        final scroll = !fits(display);
        painter.dispose();
        final changed = display != value || scroll;
        final text = Text(display, maxLines: 1, softWrap: false, style: style);
        final child = SizedBox(
          height: valueTextHeight(context, style),
          child: Align(
            alignment: alignment,
            child: scroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: text,
                  )
                : text,
          ),
        );
        if (!changed) return child;
        if (!revealOnTap) return Tooltip(message: value, child: child);
        return Semantics(
          label: '${label == null ? '' : '$label: '}$value',
          button: true,
          excludeSemantics: true,
          child: Tooltip(
            message: value,
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(label ?? 'Nilai lengkap'),
                  content: SingleChildScrollView(
                    child: SelectableText(
                      value,
                      style: niraText(NiraType.section),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}
