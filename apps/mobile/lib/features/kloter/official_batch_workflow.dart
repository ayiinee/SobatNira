import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../pekerjaan/review_api.dart';
import 'batch_detail_page.dart';
import 'demo_production.dart';
import 'juice_volume.dart';
import 'kloter_detail_widgets.dart';
import 'kloter_detail_page.dart';
import '../laporan/connected_reports.dart';

String _errorText(Object? error) => error is ReviewApiError
    ? (error.status == 404 ? error.message : error.detail ?? error.message)
    : 'Hasil belum terkonfirmasi. Muat ulang atau coba permintaan yang sama.';

class OfficialLotBatches extends StatefulWidget {
  const OfficialLotBatches({
    required this.api,
    required this.scope,
    required this.lotId,
    this.synthetic = false,
    required this.kloterCode,
    required this.caneWeight,
    this.kloter,
    required this.onOpenPekerjaan,
    required this.millingRevision,
    required this.canCreate,
    required this.onNavigate,
    required this.onChanged,
    required this.reportLink,
    super.key,
  });

  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;
  final bool synthetic;
  final String kloterCode;
  final String caneWeight;
  final DemoKloter? kloter;
  final VoidCallback onOpenPekerjaan;
  final String? millingRevision;
  final bool canCreate;
  final ValueChanged<NiraTab> onNavigate;
  final VoidCallback onChanged;
  final Future<void> Function([String? batchId]) reportLink;

  @override
  State<OfficialLotBatches> createState() => _OfficialLotBatchesState();
}

class _OfficialLotBatchesState extends State<OfficialLotBatches> {
  int _offset = 0;
  late Future<Json> _result = _load();
  Future<Json> _load() => widget.api.factoryBatches(
    widget.scope,
    widget.lotId,
    offset: _offset,
    synthetic: widget.synthetic,
  );

  void _reload() {
    final result = _load();
    setState(() {
      _result = result;
    });
  }

  Future<void> _create() async {
    final id = ReviewApi.requestUuid();
    final today = DateTime.now().toIso8601String().substring(0, 16);
    final created = await _form(
      context,
      'Tambah batch',
      [
        const _Field('Kode batch'),
        const _Field('Nomor wajan', kind: _Input.integer),
        _Field('Waktu pemasakan', initial: today, kind: _Input.date),
        const _Field('Volume nira (mL)', kind: _Input.quantity),
        const _Field('Hasil fisik (kg)', kind: _Input.quantity),
        const _Field('Grade'),
        const _Field('Berat grade (kg)', kind: _Input.quantity),
        const _Field('Harga per kg (Rp)', kind: _Input.money),
      ],
      (v) => widget.api.createBatch(widget.scope, {
        'id': id,
        'lotId': widget.lotId,
        'code': v[0],
        'wokNumber': int.parse(v[1]),
        'occurredAt': DateTime.parse(v[2]).toUtc().toIso8601String(),
        'quantityMl': v[3],
        'physicalWeightKg': v[4],
        'grades': [
          {'code': v[5], 'weightKg': v[6], 'pricePerKgRupiah': v[7]},
        ],
      }),
    );
    if (!mounted) return;
    if (created != null) {
      await _open(created, created: true);
    } else {
      _reload();
    }
  }

  Future<void> _open(Json batch, {bool created = false}) async {
    final api = widget.api;
    final scope = widget.scope;
    var changed = created;
    var returned = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _OfficialBatchDetail(
          api: api,
          scope: scope,
          initial: batch,
          kloterCode: widget.kloterCode,
          caneWeight: widget.caneWeight,
          kloter: widget.kloter,
          onOpenPekerjaan: widget.onOpenPekerjaan,
          millingRevision: widget.millingRevision,
          onNavigate: widget.onNavigate,
          reportLink: widget.reportLink,
          onChanged: () {
            changed = true;
            if (returned && mounted) {
              _reload();
              widget.onChanged();
            }
          },
        ),
      ),
    );
    returned = true;
    if (mounted && changed) {
      _reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _result,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const NiraLoading(label: 'Memuat data batch…');
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            Text(_errorText(snapshot.error)),
            TextButton(
              onPressed: _reload,
              child: const Text('Coba lagi memuat batch'),
            ),
          ],
        );
      }
      final batches = (snapshot.requireData['items'] as List).cast<Json>();
      bool needsReview(Json batch) =>
          batch['status'] == 'draft' || batch['hasCorrection'] == true;
      final pendingCount = batches.where(needsReview).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (batches.isEmpty)
            Text(
              'Belum ada batch',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          if (batches.isNotEmpty)
            Text(
              pendingCount > 0
                  ? '$pendingCount Batch perlu ditinjau'
                  : 'Semua batch telah ditinjau',
              style: niraText(
                NiraType.caption,
                color: pendingCount > 0 ? niraOchre : niraLeaf,
              ),
            ),
          const SizedBox(height: NiraSpace.md),
          for (final batch in batches)
            Padding(
              padding: const EdgeInsets.only(bottom: NiraSpace.md),
              child: KloterBatchTile(
                title: batch['code'] as String,
                pending: needsReview(batch) || batch['status'] == 'cancelled',
                cancelled: batch['status'] == 'cancelled',
                juice:
                    '${reportNumber(millilitersToLiters(batch['quantity_ml'] as String))} L',
                physicalWeight:
                    '${reportNumber(batch['physical_weight_kg'])} kg',
                onTap: () => _open(batch),
              ),
            ),
          if (widget.canCreate) DocumentLink('Tambah batch', _create),
          if (_offset > 0 || batches.length == 20)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _offset == 0
                      ? null
                      : () {
                          _offset -= 20;
                          _reload();
                        },
                  child: const Text('Sebelumnya'),
                ),
                TextButton(
                  onPressed: batches.length < 20
                      ? null
                      : () {
                          _offset += 20;
                          _reload();
                        },
                  child: const Text('Berikutnya'),
                ),
              ],
            ),
        ],
      );
    },
  );
}

class _OfficialBatchDetail extends StatefulWidget {
  const _OfficialBatchDetail({
    required this.api,
    required this.scope,
    required this.initial,
    required this.kloterCode,
    required this.caneWeight,
    this.kloter,
    required this.onOpenPekerjaan,
    required this.millingRevision,
    required this.onNavigate,
    required this.reportLink,
    required this.onChanged,
  });

  final ReviewApi api;
  final FactoryScope scope;
  final Json initial;
  final String kloterCode;
  final String caneWeight;
  final DemoKloter? kloter;
  final VoidCallback onOpenPekerjaan;
  final String? millingRevision;
  final ValueChanged<NiraTab> onNavigate;
  final Future<void> Function([String? batchId]) reportLink;
  final VoidCallback onChanged;

  @override
  State<_OfficialBatchDetail> createState() => _OfficialBatchDetailState();
}

typedef _BatchRead = ({Json? current, Json? legacyBatch});

class _OfficialBatchDetailState extends State<_OfficialBatchDetail> {
  late final String _id = widget.initial['id'] as String;
  late final String _lot = widget.initial['lot_id'] as String;
  late Future<_BatchRead> _detail = _load();
  late final _photo = widget.millingRevision == null
      ? null
      : widget.api
            .approvedPhoto(
              widget.scope,
              widget.millingRevision!,
              variant: 'preview',
            )
            .then((photo) => photo, onError: (Object _) => null);
  bool _busy = false;
  ({String id, String reason, String? closureId})? _openingCorrection;
  String? _error;
  String? _notice;

  Future<_BatchRead> _load() async {
    try {
      return (
        current: await widget.api.factoryBatch(widget.scope, _id),
        legacyBatch: null,
      );
    } on ReviewApiError catch (error) {
      if (error.status != 404 ||
          error.detail?.startsWith('Cannot GET ') != true) {
        rethrow;
      }
    }
    if (widget.initial['status'] != 'approved') {
      return (current: null, legacyBatch: null);
    }
    try {
      final report = await widget.api.lotProductionReport(
        widget.scope,
        _lot,
        synthetic: widget.initial['is_synthetic'] == true,
      );
      final lot = (report['items'] as List)
          .cast<Json>()
          .where((lot) => lot['lotId'] == _lot)
          .firstOrNull;
      final batches = (lot?['batches'] as List? ?? const []).cast<Json>();
      return (
        current: null,
        legacyBatch: batches.where((batch) => batch['id'] == _id).firstOrNull,
      );
    } catch (_) {
      return (current: null, legacyBatch: null);
    }
  }

  void _reload() {
    setState(() {
      _detail = _load();
    });
  }

  void _applyCorrection(Json? correction, {bool reopened = false}) {
    _detail = _detail.then(
      (batch) => (
        current: {
          ...batch.current!,
          'correction': correction,
          if (reopened) ...{'lotClosed': false, 'lotClosureId': null},
        },
        legacyBatch: null,
      ),
    );
  }

  Future<void> _costs() async {
    final result = await showLotCostsForm(
      context,
      widget.api,
      widget.scope,
      _lot,
      widget.kloterCode,
    );
    if (mounted && result != null) {
      widget.onChanged();
      _reload();
    }
  }

  Future<void> _run(
    Future<Json> Function() operation, {
    String? confirmation,
    String? notice,
    void Function(Json)? apply,
  }) async {
    if (_busy) return;
    if (confirmation != null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(confirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Kembali'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Lanjutkan'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true || _busy) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await operation();
      widget.onChanged();
      if (mounted) {
        _notice = notice;
        if (apply == null) {
          _detail = _load();
        } else {
          apply(result);
        }
      }
    } catch (error) {
      if (mounted) {
        _error = _errorText(error);
        _detail = _load();
      }
      // A transport error can follow a successful commit. Refresh on return too.
      widget.onChanged();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openCorrection(String? closureId) async {
    if (_busy) return;
    final result = await _form(
      context,
      'Buka koreksi batch?',
      [
        _Field(
          'Alasan koreksi',
          kind: _Input.reason,
          initial: _openingCorrection?.reason ?? '',
        ),
      ],
      (values) {
        final reason = values.single;
        final previous = _openingCorrection;
        final id =
            previous != null &&
                previous.reason == reason &&
                previous.closureId == closureId
            ? previous.id
            : ReviewApi.requestUuid();
        _openingCorrection = (id: id, reason: reason, closureId: closureId);
        return widget.api.openBatchCorrection(
          widget.scope,
          _id,
          id,
          reason,
          reopenClosureId: closureId,
        );
      },
      message: closureId == null
          ? 'Stok dan laporan tetap memakai data sah terakhir sampai koreksi divalidasi.'
          : 'Kloter akan dibuka kembali dan masuk Perlu ditinjau. Stok dan laporan tetap memakai data sah terakhir sampai koreksi divalidasi.',
    );
    if (!mounted || result == null) return;
    _openingCorrection = null;
    widget.onChanged();
    setState(() {
      _error = null;
      _notice = null;
      _applyCorrection(result, reopened: closureId != null);
    });
  }

  Future<void> _editCorrection(Json correction, {int? gradeIndex}) async {
    final data = correction['proposed_data'] as Json;
    final grades = (data['grades'] as List).cast<Json>().toList();
    final editingWeight = gradeIndex == null;
    final grade = editingWeight || gradeIndex >= grades.length
        ? null
        : grades[gradeIndex];
    final result = await _form(
      context,
      editingWeight
          ? 'Edit berat hasil'
          : grade == null
          ? 'Tambah grade'
          : 'Edit grade',
      editingWeight
          ? [
              _Field(
                'Berat hasil (kg)',
                kind: _Input.quantity,
                initial: data['physicalWeightKg'] as String,
              ),
            ]
          : [
              _Field('Grade', initial: grade?['code'] as String? ?? ''),
              _Field(
                'Berat grade (kg)',
                kind: _Input.quantity,
                initial: grade?['weightKg'] as String? ?? '',
              ),
              _Field(
                'Harga per kg (Rp)',
                kind: _Input.money,
                initial: grade?['pricePerKgRupiah'] as String? ?? '',
              ),
            ],
      (values) => widget.api.saveBatchCorrection(
        widget.scope,
        _id,
        correction['id'] as String,
        {
          'version': correction['version'],
          'physicalWeightKg': editingWeight
              ? values.single
              : data['physicalWeightKg'],
          'grades': editingWeight
              ? grades
              : [
                  ...grades.take(gradeIndex),
                  {
                    'code': values[0],
                    'weightKg': values[1],
                    'pricePerKgRupiah': values[2],
                  },
                  ...grades.skip(gradeIndex + 1),
                ],
        },
      ),
    );
    if (mounted && result != null) {
      widget.onChanged();
      setState(() => _applyCorrection(result));
    }
  }

  Future<void> _finishCorrection(Json correction, {bool discard = false}) {
    final correctionId = correction['id'] as String;
    return _run(
      () => widget.api.finishBatchCorrection(
        widget.scope,
        _id,
        correctionId,
        correction['version'] as int,
        discard: discard,
      ),
      confirmation: discard
          ? 'Buang draf koreksi? Data sah tetap berlaku.'
          : null,
      notice: discard ? null : 'Koreksi batch berhasil divalidasi',
      apply: discard ? (_) => _applyCorrection(null) : null,
    );
  }

  List<Widget> _correctionActions(Json correction, bool editable) {
    final data = correction['proposed_data'] as Json;
    final grades = (data['grades'] as List).cast<Json>();
    return [
      for (final (index, grade) in grades.indexed)
        ListTile(
          title: Text('Grade ${grade['code']}'),
          subtitle: Text(
            '${reportNumber(grade['weightKg'])} kg · ${reportMoney(grade['pricePerKgRupiah'])}/kg',
          ),
          onTap: editable
              ? () => _editCorrection(correction, gradeIndex: index)
              : null,
          trailing: editable && grades.length > 1
              ? IconButton(
                  tooltip: 'Hapus grade ${grade['code']}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _run(
                    () => widget.api.saveBatchCorrection(
                      widget.scope,
                      _id,
                      correction['id'] as String,
                      {
                        'version': correction['version'],
                        'physicalWeightKg': data['physicalWeightKg'],
                        'grades': [
                          ...grades.take(index),
                          ...grades.skip(index + 1),
                        ],
                      },
                    ),
                    confirmation:
                        'Hapus grade ${grade['code']} dari draf koreksi?',
                    apply: _applyCorrection,
                  ),
                )
              : null,
        ),
      if (editable) ...[
        TextButton(
          onPressed: () =>
              _editCorrection(correction, gradeIndex: grades.length),
          child: const Text('Tambah grade'),
        ),
        TextButton(
          onPressed: () => _finishCorrection(correction, discard: true),
          child: const Text('Buang draf koreksi'),
        ),
      ],
    ];
  }

  BatchDetailData _data(Json batch, Json? correction) {
    final date = DateTime.parse(batch['occurred_at'] as String).toLocal();
    final juice =
        '${reportNumber(millilitersToLiters(batch['quantity_ml'] as String))} L';
    final proposed = correction?['proposed_data'] as Json?;
    final physical =
        '${reportNumber(proposed?['physicalWeightKg'] ?? batch['physical_weight_kg'])} kg';
    final grades = (batch['grades'] as List? ?? const []).cast<Json>();
    return (
      summary: [
        DemoField('Nira yang dimasak', juice),
        DemoField(
          'Brix tebu acuan',
          widget.kloter?.brix == null
              ? '—'
              : formatQuantity(widget.kloter!.brix, '°Bx'),
        ),
        DemoField('Hasil timbang', physical),
      ],
      cooking: [
        DemoField('Tanggal masak', formatDate(date)),
        DemoField(
          'Jenis tebu',
          widget.kloter?.record?['caneTypeCode']?.toString() ?? '—',
        ),
        DemoField(
          'Asal nira',
          batch['status'] == 'approved' ? widget.kloter?.supplier ?? '—' : '—',
        ),
        DemoField(
          'Brix tebu acuan',
          widget.kloter?.brix == null
              ? '—'
              : formatQuantity(widget.kloter!.brix, '°Bx'),
        ),
      ],
      grades: [
        for (final grade in grades)
          (
            code: grade['code'] as String,
            weight: reportNumber(grade['weightKg']),
            price: reportMoney(grade['pricePerKgRupiah']),
          ),
      ],
      totalWeight: batch['finalSugarKg'] == null
          ? '—'
          : '${reportNumber(batch['finalSugarKg'])} kg',
      value: batch['exactValueRupiah'] == null
          ? '—'
          : reportMoney(batch['exactValueRupiah']),
      physicalWeight: physical,
      caneWeight: widget.caneWeight,
    );
  }

  List<Widget> _actions(Json batch) {
    final costSaved = batch['costSaved'] == true;
    final remaining = batch['remainingMl'] as String;
    return [
      const SizedBox(height: NiraSpace.md),
      if (batch['status'] == 'draft') ...[
        EditableFields(
          onEdit: null,
          fields: [
            DemoField('Status biaya', costSaved ? 'Tercatat' : 'Belum diisi'),
            DemoField(
              'Nira yang masih perlu direservasi',
              '${reportNumber(millilitersToLiters(remaining))} L',
            ),
          ],
        ),
      ],
      if (batch['status'] == 'approved')
        DocumentLink(
          'Nilai produksi dan margin kloter',
          () => widget.reportLink(_id),
        ),
      if (batch['status'] == 'draft' &&
          !_busy &&
          widget.initial['is_synthetic'] != true &&
          widget.scope.role == 'admin') ...[
        NiraButton(
          costSaved ? 'Edit biaya kloter' : 'Isi biaya kloter',
          _costs,
        ),
        if (costSaved && remaining != '0')
          NiraButton(
            'Reservasi nira',
            () => _run(
              () => widget.api.reserveBatchJuice(
                widget.scope,
                _lot,
                _id,
                remaining,
              ),
            ),
          ),
        TextButton(
          onPressed: () => _run(
            () => widget.api.finishBatch(widget.scope, _id, cancel: true),
            confirmation: 'Batalkan draf dan lepaskan reservasi aktif?',
          ),
          child: const Text('Batalkan draf'),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_BatchRead>(
    future: _detail,
    builder: (_, snapshot) {
      final current = snapshot.data?.current;
      final legacy = snapshot.hasData && current == null;
      final reportedBatch = snapshot.data?.legacyBatch;
      final status = current?['status'] ?? widget.initial['status'];
      final approved = status == 'approved';
      final pending = status == 'draft';
      final ready =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      final correction = current?['correction'] as Json?;
      final canCorrect = ready && current?['canCorrect'] == true && !_busy;
      final validationBlock = switch ((
        ready,
        current != null,
        widget.scope.role,
        widget.initial['is_synthetic'] == true,
        current?['lotClosed'] == true,
        current?['costSaved'] == true,
        current?['remainingMl'] == '0',
      )) {
        (false, _, _, _, _, _, _) =>
          snapshot.hasError
              ? 'Rincian batch belum bisa dimuat.'
              : 'Memuat rincian batch.',
        (_, false, _, _, _, _, _) when legacy =>
          'Validasi belum tersedia pada versi API ini.',
        (_, false, _, _, _, _, _) => 'Rincian batch belum tersedia.',
        (_, _, 'owner', _, _, _, _) =>
          'Hanya admin yang dapat memvalidasi batch.',
        (_, _, _, true, _, _, _) => 'Data contoh hanya dapat dilihat.',
        (_, _, _, _, true, _, _) =>
          'Buka kembali kloter sebelum memvalidasi batch.',
        (_, _, _, _, _, false, _) =>
          'Isi biaya kloter di Ringkasan sebelum validasi.',
        (_, _, _, _, _, _, false) =>
          'Lengkapi reservasi nira di Ringkasan sebelum validasi.',
        _ => null,
      };
      final canApprove = pending && validationBlock == null && !_busy;
      final batch = legacy ? {...widget.initial, ...?reportedBatch} : current;
      return BatchDetailPage.official(
        officialTitle: widget.initial['code'] as String,
        kloterCode: widget.kloterCode,
        officialReviewed: approved,
        officialNotice: _notice,
        officialCancelled: status == 'cancelled',
        officialData: batch == null ? null : _data(batch, correction),
        officialDocument: widget.onOpenPekerjaan,
        officialPreview: ApprovedDocumentPreview(
          batch: true,
          photo: _photo,
          loadOriginal: widget.millingRevision == null
              ? null
              : () => widget.api.approvedPhoto(
                  widget.scope,
                  widget.millingRevision!,
                ),
          fallback: DocumentLink(
            'Foto nota produksi di Pekerjaan',
            widget.onOpenPekerjaan,
          ),
        ),
        officialEditWeight: correction != null && canCorrect
            ? () => _editCorrection(correction)
            : null,
        officialGradeActions: correction == null
            ? null
            : _correctionActions(correction, canCorrect),
        officialActions: current != null
            ? _actions(current)
            : [
                if (legacy && reportedBatch == null)
                  const Text('Rincian grade dan harga batch belum tersedia.'),
                if (legacy && approved)
                  DocumentLink(
                    'Nilai produksi dan margin kloter',
                    () => widget.reportLink(_id),
                  ),
              ],
        officialStatus: snapshot.hasError
            ? Column(
                children: [
                  Text(_errorText(snapshot.error)),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Muat ulang batch'),
                  ),
                ],
              )
            : const LinearProgressIndicator(
                semanticsLabel: 'Memuat data batch',
              ),
        officialAction: approved || pending || _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy || (current != null && !ready))
                    const LinearProgressIndicator(
                      semanticsLabel: 'Memperbarui batch',
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: niraText(
                        NiraType.caption,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (pending && validationBlock != null)
                    Text(
                      validationBlock,
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                  if (approved || pending)
                    BatchReviewActions(
                      batchNumber: widget.initial['wok_number'] as int,
                      batchCode: widget.initial['code'] as String,
                      label: correction != null
                          ? 'Validasi ulang'
                          : approved
                          ? 'Batch tervalidasi'
                          : 'Validasi',
                      verified: approved && correction == null,
                      enabled: correction != null ? canCorrect : canApprove,
                      onCorrection: canCorrect && correction == null
                          ? () => _openCorrection(
                              current?['lotClosureId'] as String?,
                            )
                          : null,
                      revalidating: correction != null,
                      onVerify: correction != null
                          ? () => _finishCorrection(correction)
                          : () => _run(
                              () => widget.api.finishBatch(widget.scope, _id),
                            ),
                    ),
                ],
              )
            : null,
        onNavigate: widget.onNavigate,
      );
    },
  );
}

Future<Json?> showLotCostsForm(
  BuildContext context,
  ReviewApi api,
  FactoryScope scope,
  String lotId,
  String kloterCode, {
  bool correction = false,
}) async {
  Future<Json?> read() async {
    final cost = await api.lotCosts(scope, lotId);
    if (!correction && cost?['frozen'] == true) {
      throw const ReviewApiError(
        409,
        code: 'LOT_COST_FROZEN',
        detail: 'Biaya historis sudah dibekukan. Ajukan koreksi biaya.',
      );
    }
    return cost;
  }

  Json? cost;
  try {
    cost = await read();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_costErrorText(error))));
    }
    return null;
  }
  if (!context.mounted) return null;
  if (correction && cost == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Biaya awal kloter belum tersedia.')),
    );
    return null;
  }
  final requestId = correction ? ReviewApi.requestUuid() : null;

  const labels = [
    'Biaya tebu (Rp)',
    'Biaya operasional (Rp)',
    'Biaya bahan (Rp)',
    'Biaya lain (Rp)',
  ];
  const keys = [
    'cane_rupiah',
    'operational_rupiah',
    'ingredient_rupiah',
    'other_rupiah',
  ];
  return _form(
    context,
    correction
        ? 'Koreksi biaya kloter $kloterCode'
        : 'Biaya kloter $kloterCode',
    [
      for (final (index, key) in keys.indexed)
        _Field(
          labels[index],
          kind: _Input.money,
          initial: cost?[key]?.toString() ?? '',
        ),
      if (correction) const _Field('Alasan koreksi', kind: _Input.reason),
    ],
    (values) {
      final payload = {
        'version': cost?['version'] ?? 0,
        'caneCostRupiah': values[0],
        'operationalCostRupiah': values[1],
        'ingredientCostRupiah': values[2],
        'otherCostRupiah': values[3],
      };
      return requestId == null
          ? api.saveLotCosts(scope, lotId, payload)
          : api.requestLotCostCorrection(scope, lotId, requestId, {
              ...payload,
              'reason': values[4],
            });
    },
    reloadOnConflict: () async {
      cost = await read();
      return [
        'Biaya terbaru di server',
        for (final (index, key) in keys.indexed)
          '${labels[index]}: ${cost?[key]?.toString() ?? '—'}',
        'Periksa masukan Anda sebelum menyimpan kembali.',
      ].join('\n');
    },
  );
}

String _costErrorText(Object? error) =>
    error is ReviewApiError && error.status == 409
    ? error.detail ?? _errorText(error)
    : _errorText(error);

enum _Input { text, reason, integer, date, quantity, money }

class _Field {
  const _Field(this.label, {this.kind = _Input.text, this.initial = ''});
  final String label;
  final _Input kind;
  final String initial;
}

Future<Json?> _form(
  BuildContext context,
  String title,
  List<_Field> fields,
  Future<Json> Function(List<String>) save, {
  String? message,
  Future<String> Function()? reloadOnConflict,
}) => showDialog<Json>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ProductionForm(
    title: title,
    fields: fields,
    save: save,
    message: message,
    reloadOnConflict: reloadOnConflict,
  ),
);

class _ProductionForm extends StatefulWidget {
  const _ProductionForm({
    required this.title,
    required this.fields,
    required this.save,
    this.message,
    this.reloadOnConflict,
  });
  final String title;
  final List<_Field> fields;
  final Future<Json> Function(List<String>) save;
  final String? message;
  final Future<String> Function()? reloadOnConflict;

  @override
  State<_ProductionForm> createState() => _ProductionFormState();
}

class _ProductionFormState extends State<_ProductionForm> {
  final _form = GlobalKey<FormState>();
  late final _inputs = widget.fields
      .map((field) => TextEditingController(text: field.initial))
      .toList();
  bool _busy = false;
  List<String>? _pending;
  String? _error;
  String? _latest;
  bool _requiresReload = false;
  bool _frozen = false;

  @override
  void dispose() {
    for (final input in _inputs) {
      input.dispose();
    }
    super.dispose();
  }

  String? _validate(String? value, _Input kind) {
    final text = value?.trim() ?? '';
    final valid = switch (kind) {
      _Input.text => text.isNotEmpty && text.length <= 100,
      _Input.reason => text.isNotEmpty && text.length <= 500,
      _Input.date => DateTime.tryParse(text) != null,
      _Input.integer =>
        (int.tryParse(text) ?? 0) >= 1 && int.parse(text) <= 10000,
      _Input.money => RegExp(r'^\d{1,30}$').hasMatch(text),
      _Input.quantity =>
        RegExp(r'^\d{1,24}([.,]\d{1,6})?$').hasMatch(text) &&
            (num.tryParse(text.replaceAll(',', '.')) ?? 0) > 0,
    };
    return valid ? null : 'Periksa nilai ini.';
  }

  Future<void> _submit() async {
    if (_pending == null && !_form.currentState!.validate()) return;
    final values =
        _pending ??
        [
          for (final (i, field) in widget.fields.indexed)
            if (field.kind == _Input.quantity)
              _inputs[i].text.trim().replaceAll(',', '.')
            else
              _inputs[i].text.trim(),
        ];
    setState(() {
      _pending = values;
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.save(values);
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error is ReviewApiError &&
            error.status >= 400 &&
            error.status < 500 &&
            error.status != 408 &&
            error.status != 429) {
          _pending = null;
        }
        if (widget.reloadOnConflict != null &&
            error is ReviewApiError &&
            error.status == 409) {
          _latest = null;
          _frozen = error.code == 'LOT_COST_FROZEN';
          _requiresReload = !_frozen;
          _error = _costErrorText(error);
        } else {
          _error = _errorText(error);
        }
      });
    }
  }

  Future<void> _reloadConflict() async {
    setState(() => _busy = true);
    try {
      final latest = await widget.reloadOnConflict!();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _error = null;
        _requiresReload = false;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _frozen = error is ReviewApiError && error.code == 'LOT_COST_FROZEN';
        _requiresReload = !_frozen;
        _error = _costErrorText(error);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.message case final message?) Text(message),
                for (final (i, field) in widget.fields.indexed)
                  TextFormField(
                    controller: _inputs[i],
                    enabled: _pending == null,
                    maxLines: field.kind == _Input.reason ? 3 : 1,
                    maxLength: field.kind == _Input.reason ? 500 : null,
                    keyboardType: switch (field.kind) {
                      _Input.integer || _Input.money => TextInputType.number,
                      _Input.quantity => const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      _ => null,
                    },
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.kind == _Input.date
                          ? 'YYYY-MM-DDTHH:MM'
                          : null,
                    ),
                    validator: (value) => _validate(value, field.kind),
                  ),
                if (_error != null) Text(_error!),
                if (_latest case final latest?) Text(latest),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(widget.message == null ? 'Tutup' : 'Batal'),
        ),
        if (_requiresReload)
          TextButton(
            onPressed: _busy ? null : _reloadConflict,
            child: const Text('Muat biaya terbaru'),
          ),
        FilledButton(
          onPressed: _busy || _requiresReload || _frozen ? null : _submit,
          child: Text(
            _busy
                ? 'Menyimpan…'
                : _pending != null
                ? 'Coba lagi'
                : widget.message == null
                ? 'Simpan'
                : 'Konfirmasi',
          ),
        ),
      ],
    ),
  );
}
