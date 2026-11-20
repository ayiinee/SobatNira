import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';

enum KloterPeriod {
  today('Hari ini'),
  week('Minggu ini'),
  month('Bulan ini'),
  year('Tahun ini'),
  custom('Rentang tanggal');

  const KloterPeriod(this.label);
  final String label;
}

class KloterDateFilter {
  const KloterDateFilter(this.period, this.range);

  factory KloterDateFilter.preset(KloterPeriod period, {DateTime? today}) {
    final day = DateUtils.dateOnly(today ?? DemoProduction.today);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    final DateTimeRange range = switch (period) {
      KloterPeriod.today => DateTimeRange(start: day, end: day),
      KloterPeriod.week => DateTimeRange(
        start: weekStart,
        end: weekStart.add(const Duration(days: 6)),
      ),
      KloterPeriod.month => DateTimeRange(
        start: DateTime(day.year, day.month),
        end: DateTime(day.year, day.month + 1, 0),
      ),
      KloterPeriod.year => DateTimeRange(
        start: DateTime(day.year),
        end: DateTime(day.year, 12, 31),
      ),
      KloterPeriod.custom => throw ArgumentError.value(period),
    };
    return KloterDateFilter(period, range);
  }

  final KloterPeriod period;
  final DateTimeRange range;

  bool contains(DateTime date) {
    final day = DateUtils.dateOnly(date);
    return !day.isBefore(DateUtils.dateOnly(range.start)) &&
        !day.isAfter(DateUtils.dateOnly(range.end));
  }
}

// A null result closes the dialog. An empty selection applies Reset.
typedef KloterFilterResult = ({KloterDateFilter? selection});

Future<KloterFilterResult?> showKloterDateFilter(
  BuildContext context,
  KloterDateFilter? current, {
  DateTime? today,
}) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Tutup filter tanggal',
  barrierColor: const Color(0x66000000),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180),
  pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
    child: Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: niraPageInset(context).clamp(NiraSpace.lg, NiraSpace.xl),
          vertical: NiraSpace.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Material(
            key: const ValueKey('kloter-date-dialog'),
            color: Colors.white,
            elevation: 7,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(child: _FilterPanel(current, today)),
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: ScaleTransition(
          scale: animation.drive(
            Tween(
              begin: .98,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
);

class _FilterPanel extends StatefulWidget {
  const _FilterPanel(this.current, this.today);

  final DateTime? today;

  final KloterDateFilter? current;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  bool _showRange = false;

  void _apply(KloterDateFilter? filter) =>
      Navigator.pop<KloterFilterResult>(context, (selection: filter));

  @override
  Widget build(BuildContext context) {
    if (_showRange) {
      final current = widget.current;
      final today = DateUtils.dateOnly(widget.today ?? DemoProduction.today);
      return _RangeEditor(
        initialRange:
            current?.range ??
            DateTimeRange(
              start: DateTime(today.year, today.month, today.day - 9),
              end: today,
            ),
        onBack: () => setState(() => _showRange = false),
        onApply: (range) =>
            _apply(KloterDateFilter(KloterPeriod.custom, range)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NiraSpace.lg,
        NiraSpace.md,
        NiraSpace.lg,
        NiraSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tutup filter tanggal',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: niraLeaf, size: 22),
                ),
                Expanded(
                  child: Text(
                    'Filter tanggal',
                    textAlign: TextAlign.center,
                    style: niraText(NiraType.section, weight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => _apply(null),
                  style: TextButton.styleFrom(
                    foregroundColor: niraLeaf,
                    textStyle: niraText(
                      NiraType.caption,
                      weight: FontWeight.w700,
                    ),
                    minimumSize: const Size(48, 44),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          const SizedBox(height: NiraSpace.sm),
          for (final period in KloterPeriod.values) ...[
            _periodRow(period),
            if (period != KloterPeriod.values.last)
              const Divider(
                height: 1,
                thickness: 1,
                indent: NiraSpace.md,
                endIndent: NiraSpace.md,
                color: niraLine,
              ),
          ],
        ],
      ),
    );
  }

  Widget _periodRow(KloterPeriod period) {
    final custom = period == KloterPeriod.custom;
    final selected = period == widget.current?.period;
    final filter = custom
        ? null
        : KloterDateFilter.preset(period, today: widget.today);
    final caption = custom
        ? selected
              ? _describeRange(widget.current!.range)
              : 'Pilih tanggal mulai dan selesai'
        : _describeRange(filter!.range);
    return Material(
      color: selected ? const Color(0xFFE8F1E5) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(niraRadius),
      ),
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(niraRadius),
          hoverColor: const Color(0x14174B35),
          onTap: custom
              ? () => setState(() => _showRange = true)
              : () => _apply(filter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiraSpace.md,
                vertical: NiraSpace.md,
              ),
              child: Row(
                children: [
                  Icon(
                    switch (period) {
                      KloterPeriod.today => Icons.event_rounded,
                      KloterPeriod.week => Icons.view_week_rounded,
                      KloterPeriod.month => Icons.calendar_view_month_rounded,
                      KloterPeriod.year => Icons.event_note_rounded,
                      KloterPeriod.custom => Icons.filter_alt_rounded,
                    },
                    size: 23,
                    color: niraGreen,
                  ),
                  const SizedBox(width: NiraSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          period.label,
                          style: niraText(
                            NiraType.body,
                            weight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: NiraSpace.xs),
                        Text(
                          caption,
                          style: niraText(NiraType.caption, color: niraLeaf),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 22, color: niraGreen)
                  else if (custom)
                    const Icon(Icons.chevron_right, size: 18, color: niraGreen),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _describeRange(DateTimeRange range) {
  final (:start, :end) = (start: range.start, end: range.end);
  if (start == end) return formatDate(start);
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${formatMonth(end)}';
  }
  if (start.year == end.year) {
    final first = '${start.day} ${monthName(start).substring(0, 3)}';
    return '$first – ${formatDate(end, short: true)}';
  }
  return '${formatDate(start, short: true)} – ${formatDate(end, short: true)}';
}

class _RangeEditor extends StatefulWidget {
  const _RangeEditor({
    required this.initialRange,
    required this.onBack,
    required this.onApply,
  });

  final DateTimeRange initialRange;
  final VoidCallback onBack;
  final ValueChanged<DateTimeRange> onApply;

  @override
  State<_RangeEditor> createState() => _RangeEditorState();
}

class _RangeEditorState extends State<_RangeEditor> {
  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  late DateTime _start = widget.initialRange.start;
  late DateTime _end = widget.initialRange.end;
  late DateTime _month = DateTime(_start.year, _start.month);
  bool _choosingStart = true;
  bool _showSelection = false;

  bool get _valid => !_end.isBefore(_start);

  void _chooseEndpoint(bool start) {
    setState(() {
      _choosingStart = start;
      _showSelection = true;
      final day = start ? _start : _end;
      _month = DateTime(day.year, day.month);
    });
  }

  void _changeMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  void _chooseDate(DateTime day) {
    setState(() {
      if (_choosingStart) {
        _start = day;
      } else {
        _end = day;
      }
      _choosingStart = !_choosingStart;
      _showSelection = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = _month.weekday - 1;
    final rows = (days + leading + 6) ~/ 7;
    final cellHeight =
        (MediaQuery.textScalerOf(context).scale(NiraType.caption) * 1.4 + 8)
            .clamp(34.0, double.infinity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NiraSpace.lg,
        NiraSpace.sm,
        NiraSpace.lg,
        NiraSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _iconButton(
                'Kembali ke filter tanggal',
                Icons.chevron_left,
                widget.onBack,
              ),
              Expanded(
                child: Text(
                  'Rentang tanggal',
                  style: niraText(NiraType.section, weight: FontWeight.w700),
                ),
              ),
              _iconButton(
                'Tutup rentang tanggal',
                Icons.close,
                () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: NiraSpace.xs),
          Text(
            'Pilih tanggal mulai dan selesai.',
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
          const SizedBox(height: NiraSpace.lg),
          Row(
            spacing: 8,
            children: [
              Expanded(child: _dateField('Tanggal mulai', _start, true)),
              Expanded(child: _dateField('Tanggal selesai', _end, false)),
            ],
          ),
          const SizedBox(height: NiraSpace.sm),
          Row(
            children: [
              _iconButton(
                'Bulan sebelumnya',
                Icons.chevron_left,
                () => _changeMonth(-1),
              ),
              Expanded(
                child: Text(
                  formatMonth(_month),
                  textAlign: TextAlign.center,
                  style: niraText(NiraType.body, weight: FontWeight.w700),
                ),
              ),
              _iconButton(
                'Bulan berikutnya',
                Icons.chevron_right,
                () => _changeMonth(1),
              ),
            ],
          ),
          const Divider(height: 10, thickness: 1, color: niraLine),
          Row(
            children: [
              for (final day in _weekdays)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: NiraSpace.sm,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          day,
                          style: niraText(
                            NiraType.caption,
                            color: niraLeaf,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(
                      row * 7 + col - leading + 1,
                      days,
                      cellHeight,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: NiraSpace.sm),
          const Divider(height: 12, thickness: 1, color: niraLine),
          if (_valid)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _describeRange(DateTimeRange(start: _start, end: _end)),
                    style: niraText(NiraType.caption, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${DateTime.utc(_end.year, _end.month, _end.day).difference(DateTime.utc(_start.year, _start.month, _start.day)).inDays + 1} hari',
                  style: niraText(NiraType.caption, color: niraLeaf),
                ),
              ],
            )
          else
            Text(
              'Tanggal selesai harus sama atau setelah tanggal mulai.',
              style: niraText(NiraType.caption, color: const Color(0xFF8D2F22)),
            ),
          const SizedBox(height: NiraSpace.md),
          NiraButton(
            'Terapkan',
            _valid
                ? () => widget.onApply(DateTimeRange(start: _start, end: _end))
                : null,
            shadow: false,
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime date, bool start) {
    final selected = _showSelection && _choosingStart == start;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: niraText(
            NiraType.caption,
            color: niraLeaf,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: NiraSpace.sm),
        Material(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(niraRadius),
            side: BorderSide(color: selected ? niraGreen : niraLine),
          ),
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(niraRadius),
            onTap: () => _chooseEndpoint(start),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NiraSpace.sm,
                  vertical: NiraSpace.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatDate(date, short: true),
                        style: niraText(NiraType.caption),
                      ),
                    ),
                    const SizedBox(width: NiraSpace.xs),
                    const NiraIcon('calendar', 15, color: niraGreen),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayCell(int day, int days, double height) {
    if (day < 1 || day > days) return SizedBox(height: height);
    final markerSize = height - 3;
    final date = DateTime(_month.year, _month.month, day);
    final start = date == _start;
    final end = date == _end;
    final selected = start || end;
    final inRange = _valid && !date.isBefore(_start) && !date.isAfter(_end);
    return Semantics(
      label: formatDate(date),
      button: true,
      selected: selected,
      onTap: () => _chooseDate(date),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _chooseDate(date),
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (inRange && !(start && end))
                Align(
                  alignment: start
                      ? Alignment.centerRight
                      : end
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: FractionallySizedBox(
                    widthFactor: selected ? .5 : 1,
                    child: Container(
                      height: markerSize,
                      color: const Color(0xFFE5F0E5),
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? niraGreen : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: markerSize,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        style: niraText(
                          NiraType.caption,
                          weight: inRange ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? Colors.white : niraGreen,
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
    );
  }

  Widget _iconButton(String label, IconData icon, VoidCallback onPressed) =>
      IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Icon(icon, size: 18, color: niraGreen),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 39),
        padding: EdgeInsets.zero,
      );
}
