import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';

/// Paginates screen rows only; report totals and exports use the full dataset.
class ReportPaginatedList<T> extends StatefulWidget {
  const ReportPaginatedList({
    required this.items,
    required this.builder,
    this.resetToken,
    super.key,
  });

  final List<T> items;
  final Widget Function(List<T> rows) builder;
  final Object? resetToken;

  @override
  State<ReportPaginatedList<T>> createState() => _ReportPaginatedListState<T>();
}

class _ReportPaginatedListState<T> extends State<ReportPaginatedList<T>> {
  static const _pageSize = 5;
  int _page = 0;

  int get _pageCount => math.max(1, (widget.items.length / _pageSize).ceil());

  @override
  void didUpdateWidget(covariant ReportPaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) _page = 0;
    _page = math.min(_page, _pageCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, widget.items.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.builder(widget.items.sublist(start, end)),
        if (widget.items.length > _pageSize) ...[
          const SizedBox(height: NiraSpace.sm),
          Text(
            '${start + 1}–$end dari ${widget.items.length}',
            textAlign: TextAlign.center,
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
          NiraPagination(
            page: _page + 1,
            pageCount: _pageCount,
            onPrevious: _page > 0 ? () => setState(() => _page--) : null,
            onNext: _page + 1 < _pageCount
                ? () => setState(() => _page++)
                : null,
          ),
        ],
      ],
    );
  }
}
