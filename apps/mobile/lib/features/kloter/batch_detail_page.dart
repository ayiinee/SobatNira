import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';

class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({
    required this.batch,
    required this.demo,
    required this.onNavigate,
    super.key,
  });

  final DemoBatch batch;
  final DemoProduction demo;
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> {
  int _tab = 0;
  DemoBatch get _batch => widget.batch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.demo,
    builder: (context, _) {
      final reviewed = _batch.review.verified;
      return NiraScaffold(
        tab: NiraTab.kloter,
        onNavigate: widget.onNavigate,
        bottomAction: _tab == 0
            ? NiraButton(
                reviewed ? 'Batch tervalidasi' : 'Validasi',
                reviewed
                    ? null
                    : () =>
                          verifyDemoReview(context, widget.demo, _batch.review),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DetailTitle('Detail batch'),
            Padding(
              padding: const EdgeInsets.fromLTRB(niraInset, 2, niraInset, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Batch ${_batch.number}',
                      style: niraText(20.5, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ReviewBadge(reviewed: reviewed),
                ],
              ),
            ),
            NiraTabs(
              labels: const ['Ringkasan', 'Masak', 'Grade'],
              selected: _tab,
              onSelected: (index) => setState(() => _tab = index),
              height: 44,
              inset: 12,
            ),
            Expanded(
              child: ListView(
                key: ValueKey(_tab),
                padding: const EdgeInsets.fromLTRB(niraInset, 9, niraInset, 5),
                children: switch (_tab) {
                  0 => _summary(),
                  1 => _cooking(),
                  _ => _grade(),
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  List<Widget> _summary() => [
    const DocumentPreview(batch: true),
    const SizedBox(height: 10),
    const DetailSectionTitle('Ringkasan proses'),
    const SizedBox(height: 8),
    EditableFields(fields: _batch.review.fields, onEdit: _editField),
    const SizedBox(height: 9),
    const DetailSectionTitle('Harga pengesahan'),
    _priceHeader(),
    for (final entry in DemoBatch.gradePrices.entries)
      _PriceRow(
        grade: Text(entry.key, style: niraText(11.3)),
        weight: Text(
          _batch.grade == entry.key ? '${_batch.gradeWeight}Kg' : '–',
          style: niraText(11.3),
        ),
        price: Text(entry.value, style: niraText(11.3)),
        height: 30,
      ),
    _PriceRow(
      grade: Text(
        'Margin Produksi',
        style: niraText(11.2, weight: FontWeight.w700),
      ),
      weight: Text('${_batch.gradeWeight}Kg', style: niraText(11.3)),
      price: Text('Rp670.000', style: niraText(15, weight: FontWeight.w700)),
      height: 32,
      line: niraGold,
    ),
  ];

  List<Widget> _cooking() => [
    const DetailSectionTitle('Data pemasakan'),
    const SizedBox(height: 7),
    EditableFields(fields: _batch.cooking, onEdit: _editField),
    const SizedBox(height: 13),
    DocumentLink(
      'Foto pemasakan',
      () => DocumentPreview.open(context, batch: true),
    ),
  ];

  List<Widget> _grade() => [
    const DetailSectionTitle('Hasil dan Grade'),
    const SizedBox(height: 3),
    Text('Hasil timbang', style: niraText(11.7, color: niraMuted)),
    const SizedBox(height: 10),
    const DetailMetrics([
      ('Tebu bersih', '1.500Kg'),
      ('Nira tercatat', '360L'),
    ], separate: true),
    const SizedBox(height: 7),
    _priceHeader(),
    for (final grade in const ['A', 'B'])
      _PriceRow(
        grade: Text(grade, style: niraText(11.3)),
        weight: _GradeWeight(
          grade: grade,
          weight: _batch.grade == grade ? _batch.gradeWeight : '–',
          onTap: () => _editGrade(grade),
        ),
        price: Text(
          '${DemoBatch.gradePrices[grade]}/Kg',
          style: niraText(11.3),
        ),
        height: 35,
      ),
    const Divider(height: 1, color: niraLine),
  ];

  Widget _priceHeader() => _PriceRow(
    grade: Text('Grade', style: niraText(11.3, color: niraLeaf)),
    weight: Text('Berat', style: niraText(11.3, color: niraLeaf)),
    price: Text('Harga', style: niraText(11.3, color: niraLeaf)),
    height: 29,
    line: Colors.transparent,
  );

  Future<void> _editField(DemoField field) async {
    final value = await editDemoValue(
      context,
      label: field.label,
      initial: field.value,
      unit: field.unit,
    );
    if (mounted && value != null) widget.demo.edit(_batch.review, field, value);
  }

  Future<void> _editGrade(String grade) async {
    final value = await editDemoValue(
      context,
      label: 'Berat grade $grade',
      initial: _batch.grade == grade ? _batch.gradeWeight : '',
      unit: 'Kg',
    );
    if (mounted && value != null) widget.demo.setGrade(_batch, grade, value);
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.grade,
    required this.weight,
    required this.price,
    required this.height,
    this.line = niraLine,
  });

  final Widget grade;
  final Widget weight;
  final Widget price;
  final double height;
  final Color line;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: height),
    padding: const EdgeInsets.symmetric(vertical: 4),
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

class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge({required this.reviewed});

  final bool reviewed;

  @override
  Widget build(BuildContext context) {
    final textColor = reviewed || MediaQuery.highContrastOf(context)
        ? niraGreen
        : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      constraints: const BoxConstraints(maxWidth: 153),
      decoration: BoxDecoration(
        color: reviewed ? const Color(0xFFE6EFE5) : const Color(0xFFDCB95B),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: reviewed ? niraLeaf : const Color(0xFFB79845),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reviewed ? Icons.check_circle : Icons.error,
            size: 14,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              reviewed ? 'Tervalidasi' : 'Perlu ditinjau',
              style: niraText(13.5, color: textColor, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeWeight extends StatelessWidget {
  const _GradeWeight({
    required this.grade,
    required this.weight,
    required this.onTap,
  });

  final String grade;
  final String weight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Edit berat grade $grade',
    button: true,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: const BorderSide(color: niraMuted),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(weight, style: niraText(11.3)),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: niraMuted,
              child: Text('Kg', style: niraText(11.3, color: Colors.white)),
            ),
          ],
        ),
      ),
    ),
  );
}
