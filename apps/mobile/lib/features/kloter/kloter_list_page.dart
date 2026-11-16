import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_card.dart';
import 'kloter_date_filter.dart';

class KloterListPage extends StatefulWidget {
  const KloterListPage({
    required this.kloter,
    required this.onOpenKloter,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;

  @override
  State<KloterListPage> createState() => _KloterListPageState();
}

class _KloterListPageState extends State<KloterListPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _expandedDates = <DateTime, bool>{};
  KloterDateFilter? _dateFilter;
  int _activeTab = 0;

  static const _statuses = [null, KloterStatus.review, KloterStatus.done];

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _selectDate() async {
    FocusScope.of(context).unfocus();
    final result = await showKloterDateFilter(context, _dateFilter);
    if (!mounted || result == null) return;
    _scrollToTop();
    setState(() => _dateFilter = result.selection);
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final status = _statuses[_activeTab];
    final matching = widget.kloter
        .where(
          (item) =>
              item.code.toLowerCase().contains(term) &&
              (_dateFilter?.contains(item.date) ?? true),
        )
        .toList();
    final visible = matching.where(
      (item) => status == null || item.status == status,
    );
    final pending = matching
        .where((item) => item.status == KloterStatus.review)
        .length;
    final groups = <DateTime, List<DemoKloter>>{};
    for (final item in visible) {
      final date = DateUtils.dateOnly(item.date);
      groups.putIfAbsent(date, () => []).add(item);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 13, 21, 3),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: _searchBox(),
                ),
              ),
              _filterButton(context),
            ],
          ),
        ),
        NiraTabs(
          labels: const ['Semua', 'Perlu Ditinjau', 'Tuntas'],
          height: 42,
          inset: 12,
          selected: _activeTab,
          badgeIndex: 1,
          badgeCount: pending,
          onSelected: (index) {
            FocusScope.of(context).unfocus();
            _scrollToTop();
            setState(() => _activeTab = index);
          },
        ),
        Expanded(
          child: ListView(
            key: const PageStorageKey('kloter-scroll'),
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              niraInset,
              10,
              niraInset,
              MediaQuery.viewPaddingOf(context).bottom + 88,
            ),
            children: [
              if (visible.isEmpty)
                _empty()
              else
                for (final date in dates)
                  _dateAccordion(
                    date,
                    groups[date]!,
                    latest: date == dates.first,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateAccordion(
    DateTime date,
    List<DemoKloter> items, {
    required bool latest,
  }) {
    final expanded = _expandedDates[date] ?? latest;
    return Padding(
      key: ValueKey(date),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: const BorderSide(color: niraLine),
            ),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              expanded: expanded,
              child: InkWell(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _expandedDates[date] = !expanded);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatDate(date),
                            style: niraText(14.5, weight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${items.length} kloter',
                          style: niraText(11.5, color: niraLeaf),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down,
                            color: niraLeaf,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 9),
            for (final item in items) _card(item),
          ],
        ],
      ),
    );
  }

  Widget _filterButton(BuildContext context) {
    final active = _dateFilter != null;
    final label = active
        ? 'Filter tanggal: ${_dateFilter!.period.label}'
        : 'Filter tanggal';
    return Semantics(
      label: label,
      button: true,
      selected: active,
      onTap: _selectDate,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: niraGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: active
                ? const BorderSide(color: niraGold, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: _selectDate,
            borderRadius: BorderRadius.circular(7),
            child: const SizedBox.square(
              dimension: 45,
              child: Center(
                child: NiraIcon('calendar', 26, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBox() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: niraGreen, width: 1.35),
    );
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      style: niraText(13),
      cursorColor: niraGreen,
      onChanged: (_) {
        _scrollToTop();
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Telusuri Kloter berdasarkan ID',
        hintStyle: niraText(12.2),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: niraGreen, width: 2),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        prefixIcon: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 11),
          child: NiraIcon('search', 21, color: niraGreen),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _search.clear();
                  _scrollToTop();
                  setState(() {});
                },
                tooltip: 'Hapus pencarian',
                icon: const Icon(Icons.close, size: 16, color: niraGreen),
              ),
      ),
    );
  }

  Widget _card(DemoKloter item) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: KloterCard(
      kloter: item,
      onTap: () {
        FocusScope.of(context).unfocus();
        widget.onOpenKloter(item);
      },
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.only(top: 39),
    child: Column(
      children: [
        Text(
          'Kloter tidak ditemukan',
          style: niraText(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          'Coba ID, tab, atau rentang tanggal yang lain.',
          textAlign: TextAlign.center,
          style: niraText(12.5, color: niraLeaf),
        ),
      ],
    ),
  );
}
