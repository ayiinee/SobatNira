import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'report_paginated_list.dart';

class ReportTable<T> extends StatelessWidget {
  const ReportTable({
    required this.title,
    required this.columns,
    required this.rows,
    required this.scrollHeader,
    required this.resetToken,
    required this.leading,
    required this.value,
    required this.onTap,
    this.secondary,
    super.key,
  });

  final String title;
  final List<String> columns;
  final List<T> rows;
  final Widget scrollHeader;
  final Object resetToken;
  final Widget Function(T) leading;
  final String Function(T) value;
  final String Function(T)? secondary;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) => ReportPaginatedList<T>(
    items: rows,
    scrollHeader: scrollHeader,
    resetToken: resetToken,
    builder: _table,
  );

  Widget _table(List<T> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: niraText(NiraType.section, weight: FontWeight.w700)),
      const SizedBox(height: NiraSpace.sm),
      Row(
        children: [
          for (var index = 0; index < columns.length; index++)
            Expanded(
              flex: index == 0 ? 4 : 3,
              child: Text(
                columns[index],
                textAlign: index == 0 ? TextAlign.start : TextAlign.center,
                style: niraText(
                  NiraType.caption,
                  color: const Color(0xFF858B87),
                  weight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 20),
        ],
      ),
      const SizedBox(height: NiraSpace.xs),
      const Divider(height: 1, thickness: 1, color: niraLine),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NiraSpace.lg),
          child: Text(
            'Data tidak ditemukan',
            textAlign: TextAlign.center,
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
        )
      else
        for (final row in rows) ...[
          InkWell(
            onTap: () => onTap(row),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: leading(row)),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value(row),
                        textAlign: TextAlign.center,
                        style: niraText(NiraType.body),
                      ),
                    ),
                    if (columns.length > 2)
                      Expanded(
                        flex: 3,
                        child: Text(
                          secondary!(row),
                          textAlign: TextAlign.center,
                          style: niraText(NiraType.body),
                        ),
                      ),
                    const Icon(Icons.chevron_right, color: niraGreen, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: niraLine),
        ],
    ],
  );
}
