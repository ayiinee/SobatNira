import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';

/// Paginates screen rows only; report totals and exports use the full dataset.
class ReportPaginatedList<T> extends StatefulWidget {
  const ReportPaginatedList({
    required this.items,
    required this.builder,
    this.resetToken,
    this.scrollHeader,
    super.key,
  });

  final List<T> items;
  final Widget Function(List<T> rows) builder;
  final Object? resetToken;
  final Widget? scrollHeader;

  @override
  State<ReportPaginatedList<T>> createState() => _ReportPaginatedListState<T>();
}

class _ReportPaginatedListState<T> extends State<ReportPaginatedList<T>> {
  final _pageHeight = NiraPageHeight();
  static const _pageSize = 5;
  int _page = 0;

  int get _pageCount => math.max(1, (widget.items.length / _pageSize).ceil());

  @override
  void didUpdateWidget(covariant ReportPaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length <= _pageSize ||
        oldWidget.resetToken != widget.resetToken) {
      _pageHeight.reset();
    }
    if (oldWidget.resetToken != widget.resetToken) _page = 0;
    _page = math.min(_page, _pageCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, widget.items.length);
    final body = widget.builder(widget.items.sublist(start, end));
    final footer = widget.items.length <= _pageSize
        ? null
        : NiraPagination(
            page: _page + 1,
            pageCount: _pageCount,
            onPrevious: _page > 0 ? () => setState(() => _page--) : null,
            onNext: _page + 1 < _pageCount
                ? () => setState(() => _page++)
                : null,
          );
    final scrollHeader = widget.scrollHeader;
    if (scrollHeader != null) {
      return ListView(
        key: const PageStorageKey('laporan-scroll'),
        padding: EdgeInsets.fromLTRB(
          niraPageInset(context),
          NiraSpace.md,
          niraPageInset(context),
          NiraSpace.lg,
        ),
        children: [
          scrollHeader,
          body,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: NiraSpace.sm),
              child: footer,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NiraPageBody(height: _pageHeight, firstPage: _page == 0, child: body),
        ?footer,
      ],
    );
  }
}
