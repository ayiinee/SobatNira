import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'kloter_detail_widgets.dart';

class BatchDetailLayout extends StatelessWidget {
  const BatchDetailLayout({
    required this.code,
    required this.reviewed,
    required this.section,
    required this.onSection,
    required this.children,
    required this.onNavigate,
    this.tab = NiraTab.kloter,
    this.bottomAction,
    super.key,
  });
  final String code;
  final bool reviewed;
  final int section;
  final ValueChanged<int> onSection;
  final List<Widget> children;
  final ValueChanged<NiraTab> onNavigate;
  final NiraTab tab;
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) {
    final inset = niraPageInset(context);
    return NiraScaffold(
      tab: tab,
      onNavigate: onNavigate,
      bottomAction: bottomAction,
      body: KloterDetailBody(
        section: section,
        padding: EdgeInsets.fromLTRB(inset, NiraSpace.sm, inset, NiraSpace.lg),
        header: [
          const DetailTitle('Detail batch'),
          Padding(
            padding: EdgeInsets.fromLTRB(inset, NiraSpace.xs, inset, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    style: niraText(NiraType.title, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: NiraSpace.sm),
                BatchReviewBadge(reviewed: reviewed),
              ],
            ),
          ),
          NiraTabs(
            labels: const ['Ringkasan', 'Masak', 'Grade'],
            selected: section,
            onSelected: onSection,
            height: 44,
            inset: 12,
          ),
        ],
        children: children,
      ),
    );
  }
}

class BatchPriceRow extends StatelessWidget {
  const BatchPriceRow({
    required this.grade,
    required this.weight,
    required this.price,
    this.height = 35,
    this.line = niraLine,
    super.key,
  });
  final Widget grade, weight, price;
  final double height;
  final Color line;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: height),
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Expanded(flex: 40, child: grade),
        Expanded(
          flex: 27,
          child: Align(alignment: Alignment.centerLeft, child: weight),
        ),
        Expanded(
          flex: 33,
          child: Align(alignment: Alignment.centerRight, child: price),
        ),
      ],
    ),
  );
}

class BatchSummarySection extends StatelessWidget {
  const BatchSummarySection({
    required this.fields,
    required this.prices,
    required this.total,
    this.photo,
    this.footer = const [],
    super.key,
  });
  final Widget fields, total;
  final Widget? photo;
  final List<Widget> prices, footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (photo case final preview?) ...[
        preview,
        const SizedBox(height: NiraSpace.md),
      ],
      const DetailSectionTitle('Ringkasan proses'),
      const SizedBox(height: NiraSpace.sm),
      fields,
      const SizedBox(height: NiraSpace.sm),
      const DetailSectionTitle('Harga pengesahan'),
      const BatchPriceHeader(),
      ...prices,
      total,
      ...footer,
    ],
  );
}

class BatchPriceHeader extends StatelessWidget {
  const BatchPriceHeader({super.key});

  @override
  Widget build(BuildContext context) => BatchPriceRow(
    grade: Text('Grade', style: niraText(NiraType.caption, color: niraLeaf)),
    weight: Text('Berat', style: niraText(NiraType.caption, color: niraLeaf)),
    price: Text('Harga', style: niraText(NiraType.caption, color: niraLeaf)),
    height: 29,
    line: Colors.transparent,
  );
}
