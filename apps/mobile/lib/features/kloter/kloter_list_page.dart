import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_card.dart';
import 'kloter_date_filter.dart';
import '../batches/production_batch_list.dart';

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
    if (status == null) {
      for (final item in visible) {
        groups.putIfAbsent(item.date, () => []).add(item);
      }
    }

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
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => BatchListPage()),
                ),
                icon: const Icon(Icons.factory_outlined),
                tooltip: 'Batch produksi',
              ),
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
            padding: const EdgeInsets.fromLTRB(niraInset, 10, niraInset, 14),
            children: [
              if (visible.isEmpty)
                _empty()
              else if (status == null)
                for (final entry in groups.entries) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: niraMuted,
                    padding: const EdgeInsets.fromLTRB(17, 5, 8, 5),
                    child: Text(
                      formatDate(entry.key),
                      style: niraText(14.5, color: const Color(0xFF243B31)),
                    ),
                  ),
                  for (final item in entry.value) _card(item),
                  const SizedBox(height: 9),
                ]
              else
                for (final item in visible) _card(item),
            ],
          ),
        ),
      ],
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
