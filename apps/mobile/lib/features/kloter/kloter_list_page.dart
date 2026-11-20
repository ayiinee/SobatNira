import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_card.dart';
import 'kloter_date_filter.dart';

class KloterListPage extends StatefulWidget {
  const KloterListPage({
    required this.kloter,
    required this.onOpenKloter,
    this.onCreate,
    this.filterToday,
    this.statusMessage,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;
  final VoidCallback? onCreate;
  final DateTime? filterToday;
  final Widget? statusMessage;

  @override
  State<KloterListPage> createState() => _KloterListPageState();
}

class _KloterListPageState extends State<KloterListPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchGroup = Object();
  final _suggestions = OverlayPortalController();
  final _scroll = ScrollController();
  final _expandedDates = <DateTime, bool>{};
  KloterDateFilter? _dateFilter;
  int _activeTab = 0;
  int _page = 0;
  String? _selectedId;

  static const _statuses = [null, KloterStatus.review, KloterStatus.done];
  static const _datesPerPage = 10;
  static const _searchControlSize = 48.0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && _suggestions.isShowing) {
        _suggestions.hide();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _showPage(int page) {
    _scrollToTop();
    setState(() => _page = page);
  }

  String _normalizeId(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '');

  String _keyFor(DemoKloter item) => item.id ?? item.code;

  int _idRank(DemoKloter item, String term) {
    final code = _normalizeId(item.code);
    final id = _normalizeId(_keyFor(item));
    if (code == term || id == term) return 0;
    if (code.startsWith(term) || id.startsWith(term)) return 1;
    if (code.contains(term) || id.contains(term)) return 2;
    return 3;
  }

  List<DemoKloter> _matchingIds() {
    final term = _normalizeId(_search.text);
    if (term.isEmpty) return [];
    final status = _statuses[_activeTab];
    return widget.kloter.where((item) {
      return (status == null || item.status == status) &&
          (_dateFilter?.contains(item.date) ?? true) &&
          _idRank(item, term) < 3;
    }).toList()..sort((a, b) {
      final rank = _idRank(a, term).compareTo(_idRank(b, term));
      return rank == 0 ? a.code.compareTo(b.code) : rank;
    });
  }

  void _selectId(DemoKloter item) {
    _search.text = item.code;
    FocusScope.of(context).unfocus();
    _scrollToTop();
    setState(() {
      _selectedId = _keyFor(item);
      _expandedDates[DateUtils.dateOnly(item.date)] = true;
      _page = 0;
    });
  }

  void _submitSearch(String value) {
    final matches = _matchingIds();
    final exact = matches.where(
      (item) => _idRank(item, _normalizeId(value)) == 0,
    );
    if (exact.length == 1) {
      _selectId(exact.single);
    } else if (matches.length == 1) {
      _selectId(matches.single);
    }
  }

  Future<void> _selectDate() async {
    FocusScope.of(context).unfocus();
    final result = await showKloterDateFilter(
      context,
      _dateFilter,
      today: widget.filterToday,
    );
    if (!mounted || result == null) return;
    _scrollToTop();
    setState(() {
      _dateFilter = result.selection;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final idTerm = _normalizeId(term);
    final suggestions = _suggestions.isShowing && widget.statusMessage == null
        ? _matchingIds().take(5).toList()
        : <DemoKloter>[];
    final showSuggestions =
        suggestions.isNotEmpty &&
        !(suggestions.length == 1 && _idRank(suggestions.single, idTerm) == 0);
    final status = _statuses[_activeTab];
    final groups = <DateTime, List<DemoKloter>>{};
    var pending = 0;
    for (final item in widget.kloter) {
      final matchesSearch = _selectedId != null
          ? _keyFor(item) == _selectedId
          : term.isEmpty ||
                (idTerm.isNotEmpty && _idRank(item, idTerm) < 3) ||
                (item.id != null && item.supplier.toLowerCase().contains(term));
      if (!matchesSearch || !(_dateFilter?.contains(item.date) ?? true)) {
        continue;
      }
      if (item.status == KloterStatus.review) pending++;
      if (status != null && item.status != status) continue;
      final date = DateUtils.dateOnly(item.date);
      groups.putIfAbsent(date, () => []).add(item);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final pageCount = (dates.length / _datesPerPage).ceil();
    // Keep the current page if a refresh temporarily replaces the list.
    if (widget.statusMessage == null) {
      _page = _page.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
    }
    final pageDates = dates.skip(_page * _datesPerPage).take(_datesPerPage);
    final inset = niraPageInset(context);
    final tabs = NiraTabs(
      labels: const ['Semua', 'Perlu Ditinjau', 'Tuntas'],
      height: 42,
      inset: 12,
      selected: _activeTab,
      badgeIndex: 1,
      badgeCount: pending,
      onSelected: (index) {
        FocusScope.of(context).unfocus();
        _scrollToTop();
        setState(() {
          _activeTab = index;
          _page = 0;
        });
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 180;
        final searchTop = short ? NiraSpace.xs : NiraSpace.lg;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                searchTop,
                inset,
                short ? NiraSpace.xs : NiraSpace.sm,
              ),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: OverlayPortal.overlayChildLayoutBuilder(
                      controller: _suggestions,
                      child: _searchBox(showSuggestions),
                      overlayChildBuilder: (context, anchor) {
                        final height =
                            constraints.maxHeight -
                            searchTop -
                            anchor.childSize.height;
                        if (!showSuggestions || height <= 0) {
                          return const SizedBox.shrink();
                        }
                        final origin = MatrixUtils.transformPoint(
                          anchor.childPaintTransform,
                          Offset(0, anchor.childSize.height - 1),
                        );
                        return Stack(
                          children: [
                            Positioned(
                              left: origin.dx,
                              top: origin.dy,
                              width: anchor.childSize.width,
                              child: _suggestionPanel(
                                suggestions,
                                maxHeight: math.min(height, 290),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _filterButton(context),
                  if (widget.onCreate case final create?)
                    IconButton(
                      tooltip: 'Tambah kloter',
                      onPressed: create,
                      icon: const Icon(Icons.add, color: niraGreen),
                    ),
                ],
              ),
            ),
            if (!short) tabs,
            Expanded(
              child: CustomScrollView(
                key: const PageStorageKey('kloter-scroll'),
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (short) SliverToBoxAdapter(child: tabs),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      10,
                      inset,
                      NiraSpace.lg,
                    ),
                    sliver: SliverList.list(
                      children: [
                        if (widget.statusMessage case final status?)
                          status
                        else if (pageDates.isEmpty)
                          _empty()
                        else ...[
                          for (final date in pageDates)
                            _dateAccordion(
                              date,
                              groups[date]!,
                              latest: date == pageDates.first,
                            ),
                          if (pageCount > 1)
                            NiraPagination(
                              page: _page + 1,
                              pageCount: pageCount,
                              onPrevious: _page > 0
                                  ? () => _showPage(_page - 1)
                                  : null,
                              onNext: _page + 1 < pageCount
                                  ? () => _showPage(_page + 1)
                                  : null,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
      padding: const EdgeInsets.only(bottom: NiraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(niraRadius),
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
                      horizontal: NiraSpace.lg,
                      vertical: NiraSpace.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatDate(date),
                            style: niraText(
                              NiraType.body,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: NiraSpace.sm),
                        Text(
                          '${items.length} kloter',
                          style: niraText(NiraType.caption, color: niraLeaf),
                        ),
                        const SizedBox(width: NiraSpace.sm),
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
            const SizedBox(height: NiraSpace.sm),
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
            borderRadius: BorderRadius.circular(niraRadius),
          ),
          child: InkWell(
            onTap: _selectDate,
            overlayColor: niraGreenOverlay,
            borderRadius: BorderRadius.circular(niraRadius),
            child: const SizedBox.square(
              dimension: _searchControlSize,
              child: Center(
                child: NiraIcon('calendar', 26, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionPanel(
    List<DemoKloter> items, {
    required double maxHeight,
  }) => TextFieldTapRegion(
    groupId: _searchGroup,
    child: Material(
      color: Colors.white,
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(niraRadius),
        ),
        side: BorderSide(color: niraGreen),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            for (final item in items)
              ListTile(
                dense: true,
                leading: const Icon(Icons.search, size: 20),
                title: Text(item.code),
                subtitle: Text(formatDate(item.date)),
                onTap: () => _selectId(item),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _searchBox(bool showSuggestions) {
    final border = OutlineInputBorder(
      borderRadius: showSuggestions
          ? const BorderRadius.vertical(top: Radius.circular(niraRadius))
          : BorderRadius.circular(niraRadius),
      borderSide: const BorderSide(color: niraGreen, width: 1.35),
    );
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      groupId: _searchGroup,
      onTapOutside: (_) => _searchFocus.unfocus(),
      onTap: () {
        if (_search.text.isNotEmpty &&
            _selectedId == null &&
            !_suggestions.isShowing) {
          _suggestions.show();
          setState(() {});
        }
      },
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      style: niraText(NiraType.body),
      cursorColor: niraGreen,
      onChanged: (_) {
        _selectedId = null;
        _suggestions.show();
        _showPage(0);
      },
      onSubmitted: _submitSearch,
      decoration: InputDecoration(
        hintText: 'Cari ID kloter',
        hintStyle: niraText(NiraType.body, color: niraLeaf),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: NiraSpace.sm),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: niraGreen, width: 2),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        prefixIcon: const Padding(
          padding: EdgeInsets.symmetric(horizontal: NiraSpace.md),
          child: SizedBox(
            height: _searchControlSize,
            child: Center(
              widthFactor: 1,
              child: NiraIcon('search', 21, color: niraGreen),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _search.clear();
                  _selectedId = null;
                  _suggestions.hide();
                  _showPage(0);
                },
                tooltip: 'Hapus pencarian',
                icon: const Icon(Icons.close, size: 16, color: niraGreen),
              ),
      ),
    );
  }

  Widget _card(DemoKloter item) => Padding(
    padding: const EdgeInsets.only(bottom: NiraSpace.sm),
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
          style: niraText(NiraType.section, weight: FontWeight.w700),
        ),
        const SizedBox(height: NiraSpace.xs),
        Text(
          'Coba ID, tab, atau rentang tanggal yang lain.',
          textAlign: TextAlign.center,
          style: niraText(NiraType.caption, color: niraLeaf),
        ),
      ],
    ),
  );
}
