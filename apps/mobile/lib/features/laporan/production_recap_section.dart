import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'production_recap.dart';
import 'report_paginated_list.dart';

class ProductionRecapSection extends StatefulWidget {
  const ProductionRecapSection({required this.recap, super.key});
  final ProductionRecap recap;

  @override
  State<ProductionRecapSection> createState() => _ProductionRecapSectionState();
}

class _ProductionRecapSectionState extends State<ProductionRecapSection> {
  late final _expanded = ValueNotifier<String?>(
    widget.recap.kloter.firstOrNull?.code,
  );

  @override
  void dispose() {
    _expanded.dispose();
    super.dispose();
  }

  ProductionRecap get recap => widget.recap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Produksi per kloter',
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
      const SizedBox(height: NiraSpace.xs),
      Text(
        'Buka kloter untuk melihat rincian batch.',
        style: niraText(NiraType.caption, color: niraLeaf),
      ),
      const SizedBox(height: NiraSpace.sm),
      if (recap.kloter.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NiraSpace.lg),
          child: Text(
            'Tidak ada data pada periode ini.',
            style: niraText(NiraType.body, color: niraLeaf),
          ),
        ),
      ReportPaginatedList<RecapKloter>(
        items: recap.kloter,
        resetToken: recap.kloter.map((lot) => lot.code).join('|'),
        builder: (lots) => Column(
          children: [
            for (final lot in lots)
              _KloterRecap(
                key: ValueKey(lot.code),
                lot: lot,
                expanded: _expanded,
              ),
          ],
        ),
      ),
    ],
  );
}

class _KloterRecap extends StatefulWidget {
  const _KloterRecap({required this.lot, required this.expanded, super.key});
  final RecapKloter lot;
  final ValueNotifier<String?> expanded;

  @override
  State<_KloterRecap> createState() => _KloterRecapState();
}

class _KloterRecapState extends State<_KloterRecap> {
  final _horizontal = ScrollController();
  final _tile = ExpansibleController();

  @override
  void initState() {
    super.initState();
    widget.expanded.addListener(_closeIfUnselected);
  }

  void _closeIfUnselected() {
    if (widget.expanded.value != widget.lot.code && _tile.isExpanded) {
      _tile.collapse();
    }
  }

  @override
  void dispose() {
    widget.expanded.removeListener(_closeIfUnselected);
    _tile.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    return ExpansionTile(
      controller: _tile,
      initiallyExpanded: widget.expanded.value == lot.code,
      onExpansionChanged: (open) {
        if (open) {
          widget.expanded.value = lot.code;
        } else if (widget.expanded.value == lot.code) {
          widget.expanded.value = null;
        }
      },
      tilePadding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
      childrenPadding: const EdgeInsets.only(bottom: NiraSpace.lg),
      shape: const Border(bottom: BorderSide(color: niraLine)),
      collapsedShape: const Border(bottom: BorderSide(color: niraLine)),
      iconColor: niraGreen,
      collapsedIconColor: niraGreen,
      title: Text(
        lot.code,
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
      subtitle: Text(
        '${lot.supplier}\n${formatDate(lot.date)}',
        style: niraText(NiraType.caption, color: niraLeaf),
      ),
      children: [
        DetailMetrics([
          ('Tebu', lot.cane ?? 'Belum tersedia'),
          if (lot.juice != null) ('Nira dihasilkan', lot.juice!),
          ('Gula final', lot.sugar),
        ]),
        const SizedBox(height: NiraSpace.sm),
        DetailMetrics([
          ('Rendemen', lot.rendemen),
          ('Margin', lot.margin ?? 'Belum tersedia'),
        ]),
        const SizedBox(height: NiraSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${lot.caneType ?? 'Jenis tebu belum tercatat'} · ${lot.vehicle ?? 'Kendaraan belum tercatat'}',
            style: niraText(NiraType.caption, color: niraLeaf),
          ),
        ),
        const SizedBox(height: NiraSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Rincian batch',
            style: niraText(NiraType.body, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: NiraSpace.sm),
        if (lot.batches.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rincian batch belum tersedia.',
              style: niraText(NiraType.body, color: niraLeaf),
            ),
          )
        else ...[
          ReportPaginatedList<RecapBatch>(
            items: lot.batches,
            resetToken: lot.code,
            builder: (batches) => Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: PageStorageKey('batch-table-${lot.code}'),
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: NiraSpace.md),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: niraLine),
                    bottom: BorderSide(color: niraLine),
                  ),
                  children: [
                    _row(RecapBatch.columns, header: true),
                    for (final batch in batches)
                      _row(batch.cells, pending: !batch.verified),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  TableRow _row(
    List<String> cells, {
    bool header = false,
    bool pending = false,
  }) => TableRow(
    children: [
      for (final (index, cell) in cells.indexed)
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 76),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              NiraSpace.sm,
              NiraSpace.sm,
              NiraSpace.sm,
            ),
            child: Text(
              cell.replaceAll(RegExp(r'\s+'), ' '),
              style: niraText(
                header ? NiraType.caption : NiraType.body,
                color: header
                    ? niraLeaf
                    : pending && index == cells.length - 1
                    ? niraOchre
                    : niraGreen,
                weight: header ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
    ],
  );
}
