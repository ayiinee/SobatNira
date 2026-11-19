import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'demo_lot_fixture.dart';
import 'kloter_detail_widgets.dart';

typedef BatchDetailGrade = ({String code, String weight, String price});
typedef BatchDetailData = ({
  List<DemoField> summary,
  List<DemoField> cooking,
  List<BatchDetailGrade> grades,
  String totalWeight,
  String value,
  String physicalWeight,
  String caneWeight,
});

class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({
    required this.batch,
    required this.kloterCode,
    required this.demo,
    required this.onNavigate,
    super.key,
  }) : officialTitle = null,
       officialReviewed = false,
       officialCancelled = false,
       officialAction = null,
       officialData = null,
       officialStatus = null,
       officialDocument = null,
       officialPreview = null,
       officialActions = const [],
       officialNumber = null;

  const BatchDetailPage.official({
    required this.officialTitle,
    required this.officialReviewed,
    required this.officialCancelled,
    required this.officialData,
    required this.officialNumber,
    this.officialStatus,
    this.officialDocument,
    this.officialPreview,
    this.officialActions = const [],
    this.officialAction,
    required this.kloterCode,
    required this.onNavigate,
    super.key,
  }) : batch = null,
       demo = null;

  final DemoBatch? batch;
  final String kloterCode;
  final DemoProduction? demo;
  final ValueChanged<NiraTab> onNavigate;
  final String? officialTitle;
  final bool officialReviewed;
  final bool officialCancelled;
  final BatchDetailData? officialData;
  final Widget? officialStatus;
  final VoidCallback? officialDocument;
  final Widget? officialPreview;
  final List<Widget> officialActions;
  final int? officialNumber;
  final Widget? officialAction;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  DemoBatch get _batch => widget.batch!;
  DemoProduction get _demo => widget.demo!;
  bool get _official => widget.officialTitle != null;
  bool get _reviewed =>
      _official ? widget.officialReviewed : _batch.review.verified;
  BatchDetailData? get _data => widget.officialData;

  bool? _validationNotice;
  Timer? _noticeTimer;
  late final AnimationController _noticeAnimation;
  late final _noticeSlide = _noticeAnimation.drive(
    Tween(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)),
  );

  @override
  void initState() {
    super.initState();
    _noticeAnimation = AnimationController(vsync: this)
      ..addStatusListener(_onNoticeStatus);
  }

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
      _demo.verify(_batch.review);
    } else {
      _demo.reopenBatch(_batch);
    }

    _showValidation(validated);
  }

  @override
  void didUpdateWidget(covariant BatchDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_official && !oldWidget.officialReviewed && widget.officialReviewed) {
      _showValidation(true);
    }
  }

  void _showValidation(bool validated) {
    _noticeTimer?.cancel();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _noticeAnimation
      ..duration = reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 400)
      ..reverseDuration = reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240)
      ..forward(from: 0);
    setState(() => _validationNotice = validated);
  }

  @override
  Widget build(BuildContext context) {
    final safeInsets = MediaQuery.viewPaddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildScaffold(),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: safeInsets.top,
          child: const AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            ),
            child: ColoredBox(color: niraGreen),
          ),
        ),
        if (_validationNotice case final validated?)
          Positioned(
            top: safeInsets.top,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ClipRect(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    safeInsets.left + niraPageInset(context),
                    0,
                    safeInsets.right + niraPageInset(context),
                    NiraSpace.sm,
                  ),
                  child: SlideTransition(
                    position: _noticeSlide,
                    child: _BatchValidationNotice(
                      batchNumber: widget.officialNumber ?? _batch.number,
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
  }

  List<Widget> _tabContent() => switch (_tab) {
    0 => _summary(),
    1 => _cooking(),
    _ => _grade(),
  };

  Widget _buildScaffold() => !_official
      ? ListenableBuilder(
          listenable: _demo,
          builder: (context, _) => _layout(
            'Batch ${_batch.number}',
            _batch.review.verified,
            _tabContent(),
            bottomAction: BatchReviewActions(
              batchNumber: _batch.number,
              label: _batch.review.verified ? 'Batch tervalidasi' : 'Validasi',
              verified: _batch.review.verified,
              onVerify: () => _updateValidation(true),
              onReopen: () => _updateValidation(false),
            ),
          ),
        )
      : _layout(
          widget.officialTitle!,
          widget.officialReviewed,
          _data == null ? [?widget.officialStatus] : _tabContent(),
          bottomAction: widget.officialAction,
        );

  Widget _layout(
    String title,
    bool reviewed,
    List<Widget> content, {
    Widget? bottomAction,
  }) => NiraScaffold(
    tab: NiraTab.kloter,
    onNavigate: widget.onNavigate,
    bottomAction: bottomAction,
    body: KloterDetailBody(
      section: _tab,
      padding: EdgeInsets.fromLTRB(
        niraPageInset(context),
        NiraSpace.sm,
        niraPageInset(context),
        NiraSpace.xs,
      ),
      header: [
        const DetailTitle('Detail batch'),
        Padding(
          padding: EdgeInsets.fromLTRB(
            niraPageInset(context),
            NiraSpace.xs,
            niraPageInset(context),
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: niraText(NiraType.title, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: NiraSpace.sm),
              if (!widget.officialCancelled) _ReviewBadge(reviewed: reviewed),
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
      ],
      children: content,
    ),
  );

  List<BatchDetailGrade> get _grades =>
      _data?.grades ??
      [
        for (final entry in DemoBatch.gradePrices.entries)
          (
            code: entry.key,
            weight: _batch.grade == entry.key ? _batch.gradeWeight : '–',
            price: entry.value,
          ),
      ];

  String get _totalWeight => _data?.totalWeight ?? '${_batch.gradeWeight}Kg';
  String get _productionValue =>
      _data?.value ?? demoMoney(_batch.productionValue);

  List<Widget> _summary() => [
    if (!_official)
      const DocumentPreview(batch: true)
    else
      ?widget.officialPreview,
    const SizedBox(height: NiraSpace.md),
    const DetailSectionTitle('Ringkasan proses'),
    const SizedBox(height: NiraSpace.sm),
    EditableFields(
      fields: _data?.summary ?? _batch.review.fields,
      onEdit: _official || _reviewed ? null : _editField,
    ),
    const SizedBox(height: NiraSpace.sm),
    const DetailSectionTitle('Harga pengesahan'),
    _priceHeader(),
    for (final entry in _grades)
      _PriceRow(
        grade: Text(entry.code, style: niraText(NiraType.body)),
        weight: Text(
          _official || entry.weight == '–' ? entry.weight : '${entry.weight}Kg',
          style: niraText(NiraType.body),
        ),
        price: Text(entry.price, style: niraText(NiraType.body)),
        height: 30,
      ),
    _PriceRow(
      grade: Text(
        'Nilai produksi batch',
        style: niraText(NiraType.caption, weight: FontWeight.w700),
      ),
      weight: Text(_totalWeight, style: niraText(NiraType.body)),
      price: Text(
        _productionValue,
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
      height: 32,
      line: niraGold,
    ),
    ...widget.officialActions,
    if (!_official && _batch.lot != null)
      DetailMetrics([
        ('Margin kumulatif kloter (demo)', demoMoney(_batch.lot!.marginRupiah)),
      ]),
  ];

  List<Widget> _cooking() => [
    const DetailSectionTitle('Data pemasakan'),
    const SizedBox(height: NiraSpace.sm),
    EditableFields(
      fields: _data?.cooking ?? _batch.cooking,
      onEdit: _official || _reviewed ? null : _editField,
    ),
    const SizedBox(height: NiraSpace.md),
    if (!_official)
      DocumentLink(
        'Foto pemasakan',
        () => DocumentPreview.open(context, batch: true),
      )
    else if (widget.officialDocument case final open?)
      DocumentLink('Foto nota produksi di Pekerjaan', open),
  ];

  List<Widget> _grade() => [
    const DetailSectionTitle('Hasil dan Grade'),
    const SizedBox(height: NiraSpace.xs),
    Text('Hasil timbang', style: niraText(NiraType.caption, color: niraMuted)),
    const SizedBox(height: NiraSpace.md),
    DetailMetrics([
      (
        'Tebu bersih kloter',
        _data?.caneWeight ?? '${demoNumber(_batch.lot?.caneKg ?? 0)} kg',
      ),
      ('Nilai produksi batch', _productionValue),
      if (_data case final data?) ('Hasil fisik', data.physicalWeight),
    ], separate: true),
    const SizedBox(height: NiraSpace.sm),
    _priceHeader(),
    for (final grade in _grades)
      _PriceRow(
        grade: Text(grade.code, style: niraText(NiraType.body)),
        weight: _GradeWeight(
          grade: grade.code,
          weight: grade.weight,
          onTap: _official || _reviewed ? null : () => _editGrade(grade.code),
        ),
        price: Text(
          '${grade.price}/${_official ? 'kg' : 'Kg'}',
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
    if (mounted && value != null) _demo.editBatch(_batch, field, value);
  }

  Future<void> _editGrade(String grade) async {
    if (_batch.review.verified) return;
    final value = await editDemoValue(
      context,
      label: 'Berat grade $grade',
      initial: _batch.grade == grade ? _batch.gradeWeight : '',
      unit: 'Kg',
    );
    if (mounted && value != null) _demo.setGrade(_batch, grade, value);
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
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(niraRadius),
          side: const BorderSide(color: niraLine),
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
