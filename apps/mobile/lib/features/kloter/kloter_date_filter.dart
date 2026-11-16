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

  factory KloterDateFilter.preset(KloterPeriod period) {
    final day = DemoProduction.today;
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

  bool contains(DateTime day) =>
      !day.isBefore(range.start) && !day.isAfter(range.end);
}

// A null result closes the dialog. An empty selection applies Reset.
typedef KloterFilterResult = ({KloterDateFilter? selection});

Future<KloterFilterResult?> showKloterDateFilter(
  BuildContext context,
  KloterDateFilter? current,
) => showGeneralDialog(
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Material(
            key: const ValueKey('kloter-date-dialog'),
            color: Colors.white,
            elevation: 7,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(child: _FilterPanel(current)),
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
  const _FilterPanel(this.current);

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
      return _RangeEditor(
        initialRange: current?.period == KloterPeriod.custom
            ? current!.range
            : DateTimeRange(
                start: DateTime(2026, 10, 20),
                end: DemoProduction.today,
              ),
        onBack: () => setState(() => _showRange = false),
        onApply: (range) =>
            _apply(KloterDateFilter(KloterPeriod.custom, range)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
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
                    style: niraText(17, weight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => _apply(null),
                  style: TextButton.styleFrom(
                    foregroundColor: niraLeaf,
                    textStyle: niraText(12.5, weight: FontWeight.w700),
                    minimumSize: const Size(48, 44),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final period in KloterPeriod.values) ...[
            _periodRow(period),
            if (period != KloterPeriod.values.last) const SizedBox(height: 3),
          ],
        ],
      ),
    );
  }

  Widget _periodRow(KloterPeriod period) {
    final custom = period == KloterPeriod.custom;
    final selected = period == widget.current?.period;
    final filter = custom ? null : KloterDateFilter.preset(period);
    final caption = custom
        ? selected
              ? _describeRange(widget.current!.range)
              : 'Pilih tanggal mulai dan selesai'
        : _describeRange(filter!.range);
    return Material(
      color: selected ? const Color(0xFFE8F1E5) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: const Color(0x14174B35),
          onTap: custom
              ? () => setState(() => _showRange = true)
              : () => _apply(filter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    switch (period) {
                      KloterPeriod.today => Icons.today_outlined,
                      KloterPeriod.week => Icons.date_range_outlined,
                      KloterPeriod.month => Icons.calendar_month_outlined,
                      KloterPeriod.year => Icons.event_note_outlined,
                      KloterPeriod.custom => Icons.tune,
                    },
                    size: 23,
                    color: selected ? niraGreen : niraLeaf,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          period.label,
                          style: niraText(
                            14.5,
                            weight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(caption, style: niraText(12, color: niraLeaf)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 15),
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
                  style: niraText(17, weight: FontWeight.w700),
                ),
              ),
              _iconButton(
                'Tutup rentang tanggal',
                Icons.close,
                () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pilih tanggal mulai dan selesai.',
            style: niraText(10.5, color: niraLeaf),
          ),
          const SizedBox(height: 15),
          Row(
            spacing: 8,
            children: [
              Expanded(child: _dateField('Tanggal mulai', _start, true)),
              Expanded(child: _dateField('Tanggal selesai', _end, false)),
            ],
          ),
          const SizedBox(height: 9),
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
                  style: niraText(14, weight: FontWeight.w700),
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
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        day,
                        style: niraText(
                          9.5,
                          color: niraLeaf,
                          weight: FontWeight.w600,
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
                  Expanded(child: _dayCell(row * 7 + col - leading + 1, days)),
              ],
            ),
          const SizedBox(height: 8),
          const Divider(height: 12, thickness: 1, color: niraLine),
          if (_valid)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _describeRange(DateTimeRange(start: _start, end: _end)),
                    style: niraText(11.5, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${DateTime.utc(_end.year, _end.month, _end.day).difference(DateTime.utc(_start.year, _start.month, _start.day)).inDays + 1} hari',
                  style: niraText(10.5, color: niraLeaf),
                ),
              ],
            )
          else
            Text(
              'Tanggal selesai harus sama atau setelah tanggal mulai.',
              style: niraText(11.5, color: const Color(0xFF8D2F22)),
            ),
          const SizedBox(height: 12),
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
          style: niraText(10, color: niraLeaf, weight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Material(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: selected ? niraGreen : niraLine),
          ),
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _chooseEndpoint(start),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatDate(date, short: true),
                        style: niraText(11.5),
                      ),
                    ),
                    const SizedBox(width: 3),
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

  Widget _dayCell(int day, int days) {
    if (day < 1 || day > days) return const SizedBox(height: 34);
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
          height: 34,
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
                      height: 31,
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
                  dimension: 31,
                  child: Center(
                    child: Text(
                      '$day',
                      style: niraText(
                        11.5,
                        weight: inRange ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? Colors.white : niraGreen,
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
