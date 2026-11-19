import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'production_recap.dart';
import 'report_paginated_list.dart';

class ProductionRecapSection extends StatelessWidget {
  const ProductionRecapSection({required this.recap, super.key});
  final ProductionRecap recap;

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
        resetToken: recap.kloter.map((lot) => lot.identity).join('|'),
        builder: (lots) => Column(
          children: [
            for (final lot in lots)
              _KloterRecap(
                key: ValueKey(lot.identity),
                lot: lot,
                initiallyExpanded: lot.identity == recap.kloter.first.identity,
              ),
          ],
        ),
      ),
    ],
  );
}

class _KloterRecap extends StatefulWidget {
  const _KloterRecap({
    required this.lot,
    required this.initiallyExpanded,
    super.key,
  });
  final RecapKloter lot;
  final bool initiallyExpanded;

  @override
  State<_KloterRecap> createState() => _KloterRecapState();
}

class _KloterRecapState extends State<_KloterRecap> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    return ExpansionTile(
      key: PageStorageKey('rekap-${lot.identity}'),
      initiallyExpanded: widget.initiallyExpanded,
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
            resetToken: lot.identity,
            builder: (batches) => LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: PageStorageKey('batch-table-${lot.identity}'),
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: NiraSpace.md),
                  child: SizedBox(
                    width: math.max(
                      constraints.maxWidth,
                      MediaQuery.textScalerOf(context).scale(760),
                    ),
                    child: Column(
                      children: [
                        _row(RecapBatch.columns, header: true),
                        for (final batch in batches)
                          _row(batch.cells, pending: !batch.verified),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: NiraSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Geser tabel untuk melihat semua kolom.',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(
    List<String> cells, {
    bool header = false,
    bool pending = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: niraLine)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, cell) in cells.indexed)
          Expanded(
            flex: index == cells.length - 1 ? 14 : 10,
            child: Padding(
              padding: const EdgeInsets.only(right: NiraSpace.sm),
              child: Text(
                cell,
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
    ),
  );
}
