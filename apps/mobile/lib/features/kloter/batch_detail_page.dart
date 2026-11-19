import 'dart:async';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';

class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({
    required this.batch,
    required this.kloterCode,
    required this.demo,
    required this.onNavigate,
    super.key,
  });

  final DemoBatch batch;
  final String kloterCode;
  final DemoProduction demo;
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  DemoBatch get _batch => widget.batch;

  bool? _validationNotice;
  Timer? _noticeTimer;
  late final _noticeAnimation = AnimationController(vsync: this)
    ..addStatusListener(_onNoticeStatus);
  late final _noticeSlide = _noticeAnimation.drive(
    Tween(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)),
  );

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _noticeAnimation.dispose();
    super.dispose();
  }

  void _onNoticeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _noticeTimer = Timer(
        const Duration(seconds: 7),
        _noticeAnimation.reverse,
      );
    } else if (status == AnimationStatus.dismissed) {
      setState(() => _validationNotice = null);
    }
  }

  void _updateValidation(bool validated) {
    if (validated) {
      widget.demo.verify(_batch.review);
    } else {
      widget.demo.reopenBatch(_batch);
    }

    _noticeTimer?.cancel();
    setState(() => _validationNotice = validated);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _noticeAnimation
      ..duration = reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280)
      ..reverseDuration = reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240);
    if (_noticeAnimation.isCompleted) {
      _onNoticeStatus(AnimationStatus.completed);
    } else {
      _noticeAnimation.forward();
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _buildScaffold(),
      if (_validationNotice case final validated?)
        Positioned(
          top: MediaQuery.viewPaddingOf(context).top,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: ClipRect(
              child: SlideTransition(
                position: _noticeSlide,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    niraInset,
                    NiraSpace.sm,
                    niraInset,
                    NiraSpace.md,
                  ),
                  child: _BatchValidationNotice(
                    batchNumber: _batch.number,
                    kloterCode: widget.kloterCode,
                    validated: validated,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _buildScaffold() => ListenableBuilder(
    listenable: widget.demo,
    builder: (context, _) {
      final reviewed = _batch.review.verified;
      return NiraScaffold(
        tab: NiraTab.kloter,
        onNavigate: widget.onNavigate,
        bottomAction: BatchReviewActions(
          batchNumber: _batch.number,
          label: reviewed ? 'Batch tervalidasi' : 'Validasi',
          verified: reviewed,
          onVerify: () => _updateValidation(true),
          onReopen: () => _updateValidation(false),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DetailTitle('Detail batch'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                niraInset,
                NiraSpace.xs,
                niraInset,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Batch ${_batch.number}',
                      style: niraText(NiraType.title, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: NiraSpace.sm),
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
                padding: const EdgeInsets.fromLTRB(
                  niraInset,
                  NiraSpace.sm,
                  niraInset,
                  NiraSpace.xs,
                ),
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
    const SizedBox(height: NiraSpace.md),
    const DetailSectionTitle('Ringkasan proses'),
    const SizedBox(height: NiraSpace.sm),
    EditableFields(
      fields: _batch.review.fields,
      onEdit: _batch.review.verified ? null : _editField,
    ),
    const SizedBox(height: NiraSpace.sm),
    const DetailSectionTitle('Harga pengesahan'),
    _priceHeader(),
    for (final entry in DemoBatch.gradePrices.entries)
      _PriceRow(
        grade: Text(entry.key, style: niraText(NiraType.body)),
        weight: Text(
          _batch.grade == entry.key ? '${_batch.gradeWeight}Kg' : '–',
          style: niraText(NiraType.body),
        ),
        price: Text(entry.value, style: niraText(NiraType.body)),
        height: 30,
      ),
    _PriceRow(
      grade: Text(
        'Margin Produksi',
        style: niraText(NiraType.caption, weight: FontWeight.w700),
      ),
      weight: Text('${_batch.gradeWeight}Kg', style: niraText(NiraType.body)),
      price: Text(
        'Rp670.000',
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
      height: 32,
      line: niraGold,
    ),
  ];

  List<Widget> _cooking() => [
    const DetailSectionTitle('Data pemasakan'),
    const SizedBox(height: NiraSpace.sm),
    EditableFields(
      fields: _batch.cooking,
      onEdit: _batch.review.verified ? null : _editField,
    ),
    const SizedBox(height: NiraSpace.md),
    DocumentLink(
      'Foto pemasakan',
      () => DocumentPreview.open(context, batch: true),
    ),
  ];

  List<Widget> _grade() => [
    const DetailSectionTitle('Hasil dan Grade'),
    const SizedBox(height: NiraSpace.xs),
    Text('Hasil timbang', style: niraText(NiraType.caption, color: niraMuted)),
    const SizedBox(height: NiraSpace.md),
    const DetailMetrics([
      ('Tebu bersih', '1.500Kg'),
      ('Nira tercatat', '360L'),
    ], separate: true),
    const SizedBox(height: NiraSpace.sm),
    _priceHeader(),
    for (final grade in const ['A', 'B'])
      _PriceRow(
        grade: Text(grade, style: niraText(NiraType.body)),
        weight: _GradeWeight(
          grade: grade,
          weight: _batch.grade == grade ? _batch.gradeWeight : '–',
          onTap: _batch.review.verified ? null : () => _editGrade(grade),
        ),
        price: Text(
          '${DemoBatch.gradePrices[grade]}/Kg',
          style: niraText(NiraType.body),
        ),
        height: 35,
      ),
    const Divider(height: 1, color: niraLine),
  ];

  Widget _priceHeader() => _PriceRow(
    grade: Text('Grade', style: niraText(NiraType.caption, color: niraLeaf)),
    weight: Text('Berat', style: niraText(NiraType.caption, color: niraLeaf)),
    price: Text('Harga', style: niraText(NiraType.caption, color: niraLeaf)),
    height: 29,
    line: Colors.transparent,
  );

  Future<void> _editField(DemoField field) async {
    if (_batch.review.verified) return;
    final value = await editDemoValue(
      context,
      label: field.label,
      initial: field.value,
      unit: field.unit,
    );
    if (mounted && value != null) widget.demo.editBatch(_batch, field, value);
  }

  Future<void> _editGrade(String grade) async {
    if (_batch.review.verified) return;
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

class _BatchValidationNotice extends StatelessWidget {
  const _BatchValidationNotice({
    required this.batchNumber,
    required this.kloterCode,
    required this.validated,
  });

  final int batchNumber;
  final String kloterCode;
  final bool validated;

  @override
  Widget build(BuildContext context) {
    final title = validated
        ? 'Batch $batchNumber berhasil divalidasi'
        : 'Validasi Batch $batchNumber dibatalkan';
    final detail = 'Kloter $kloterCode';
    final accent = validated ? niraGreen : niraOchre;
    return Semantics(
      liveRegion: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: Material(
        color: niraPaper,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(niraRadius),
          side: BorderSide(color: accent.withValues(alpha: .3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NiraSpace.md),
          child: Row(
            children: [
              Icon(
                validated ? Icons.check_circle : Icons.info_outline,
                color: accent,
              ),
              const SizedBox(width: NiraSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: niraText(NiraType.body, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: NiraSpace.xs),
                    Text(
                      detail,
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge({required this.reviewed});

  final bool reviewed;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = reviewed ? niraGreen : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NiraSpace.sm,
        NiraSpace.xs,
        NiraSpace.sm,
        NiraSpace.xs,
      ),
      constraints: const BoxConstraints(maxWidth: 153),
      decoration: BoxDecoration(
        color: reviewed ? const Color(0xFFE6EFE5) : const Color(0xFFDCB95B),
        borderRadius: BorderRadius.circular(niraRadius),
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
            color: foregroundColor,
          ),
          const SizedBox(width: NiraSpace.xs),
          Flexible(
            child: Text(
              reviewed ? 'Tervalidasi' : 'Perlu ditinjau',
              style: niraText(
                NiraType.body,
                color: foregroundColor,
                weight: FontWeight.w700,
              ),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: onTap == null
        ? 'Berat grade $grade, terkunci'
        : 'Edit berat grade $grade',
    button: onTap != null,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(niraRadius),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: NiraSpace.sm,
                  vertical: NiraSpace.xs,
                ),
                child: Text(weight, style: niraText(NiraType.body)),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NiraSpace.sm,
                vertical: NiraSpace.xs,
              ),
              color: niraMuted,
              child: Text(
                'Kg',
                style: niraText(NiraType.caption, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
