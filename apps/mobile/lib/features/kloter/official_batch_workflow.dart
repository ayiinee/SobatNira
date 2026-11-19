import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../pekerjaan/review_api.dart';
import 'batch_detail_page.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';
import 'kloter_detail_page.dart';
import '../laporan/connected_reports.dart';

String _errorText(Object? error) => error is ReviewApiError
    ? error.detail ?? error.message
    : 'Hasil belum terkonfirmasi. Muat ulang atau coba permintaan yang sama.';

class OfficialLotBatches extends StatefulWidget {
  const OfficialLotBatches({
    required this.api,
    required this.scope,
    required this.lotId,
    required this.kloterCode,
    required this.caneWeight,
    required this.onOpenPekerjaan,
    required this.canCreate,
    required this.onNavigate,
    required this.onChanged,
    required this.reportLink,
    super.key,
  });

  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;
  final String kloterCode;
  final String caneWeight;
  final VoidCallback onOpenPekerjaan;
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
  Future<Json> _load() =>
      widget.api.factoryBatches(widget.scope, widget.lotId, offset: _offset);

  void _reload() => setState(() => _result = _load());

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
      await _open(created);
    } else {
      _reload();
    }
  }

  Future<void> _open(Json batch) async {
    final api = widget.api;
    final scope = widget.scope;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _OfficialBatchDetail(
          api: api,
          scope: scope,
          initial: batch,
          kloterCode: widget.kloterCode,
          caneWeight: widget.caneWeight,
          onOpenPekerjaan: widget.onOpenPekerjaan,
          onNavigate: widget.onNavigate,
          reportLink: widget.reportLink,
        ),
      ),
    );
    if (mounted) {
      _reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _result,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (batches.isEmpty)
            Text(
              'Belum ada batch pada halaman ini.',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          const SizedBox(height: NiraSpace.md),
          for (final batch in batches)
            Padding(
              padding: const EdgeInsets.only(bottom: NiraSpace.md),
              child: KloterBatchCard(
                title: batch['code'] as String,
                pending: batch['status'] != 'approved',
                cancelled: batch['status'] == 'cancelled',
                juice: '${reportNumber(batch['quantity_ml'])} mL',
                physical: '${reportNumber(batch['physical_weight_kg'])} kg',
                onTap: () => _open(batch),
              ),
            ),
          if (widget.canCreate) DocumentLink('Tambah batch', _create),
          DocumentLink('Produksi dan margin kloter', () => widget.reportLink()),
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
    required this.onOpenPekerjaan,
    required this.onNavigate,
    required this.reportLink,
  });

  final ReviewApi api;
  final FactoryScope scope;
  final Json initial;
  final String kloterCode;
  final String caneWeight;
  final VoidCallback onOpenPekerjaan;
  final ValueChanged<NiraTab> onNavigate;
  final Future<void> Function([String? batchId]) reportLink;

  @override
  State<_OfficialBatchDetail> createState() => _OfficialBatchDetailState();
}

class _OfficialBatchDetailState extends State<_OfficialBatchDetail> {
  late final String _id = widget.initial['id'] as String;
  late final String _lot = widget.initial['lot_id'] as String;
  late Future<Json> _detail = _load();
  bool _busy = false;
  String? _error;

  Future<Json> _load() => widget.api.factoryBatch(widget.scope, _id);
  void _reload() => setState(() => _detail = _load());

  Future<void> _costs() async {
    final result = await _form(
      context,
      'Biaya kloter',
      const [
        _Field('Biaya tebu (Rp)', kind: _Input.money),
        _Field('Biaya operasional (Rp)', kind: _Input.money),
        _Field('Biaya bahan (Rp)', kind: _Input.money),
        _Field('Biaya lain (Rp)', kind: _Input.money),
      ],
      (values) => widget.api.saveLotCosts(widget.scope, _lot, {
        'caneCostRupiah': values[0],
        'operationalCostRupiah': values[1],
        'ingredientCostRupiah': values[2],
        'otherCostRupiah': values[3],
      }),
    );
    if (mounted && result != null) _reload();
  }

  Future<void> _run(
    Future<Json> Function() operation, {
    String? confirmation,
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
      await operation();
    } catch (error) {
      if (mounted) _error = _errorText(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _detail = _load();
        });
      }
    }
  }

  BatchDetailData _data(Json batch) {
    final date = DateTime.parse(batch['occurred_at'] as String).toLocal();
    final juice = '${reportNumber(batch['quantity_ml'])} mL';
    final physical = '${reportNumber(batch['physical_weight_kg'])} kg';
    final grades = (batch['grades'] as List? ?? const []).cast<Json>();
    return (
      summary: [
        DemoField('Nira yang dimasak', juice),
        DemoField('Hasil fisik', physical),
      ],
      cooking: [
        DemoField('Wajan', '${batch['wok_number']}'),
        DemoField('Waktu pemasakan', date.toString()),
        DemoField('Volume nira', juice),
      ],
      grades: [
        for (final grade in grades)
          (
            code: grade['code'] as String,
            weight: '${reportNumber(grade['weightKg'])} kg',
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
      EditableFields(
        onEdit: null,
        fields: [
          DemoField('Status biaya', costSaved ? 'Tercatat' : 'Belum diisi'),
          DemoField('Nira yang masih perlu direservasi', '$remaining mL'),
        ],
      ),
      if (_error != null) Text(_error!),
      if (_busy) const LinearProgressIndicator(),
      if (batch['status'] == 'approved')
        DocumentLink(
          'Nilai produksi dan margin kloter',
          () => widget.reportLink(_id),
        ),
      if (batch['status'] == 'draft' &&
          !_busy &&
          widget.scope.role == 'admin') ...[
        if (!costSaved) NiraButton('Isi biaya kloter', _costs),
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
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _detail,
    builder: (_, snapshot) {
      final current = snapshot.data;
      final status = current?['status'] ?? widget.initial['status'];
      final approved = status == 'approved';
      final canApprove =
          current?['status'] == 'draft' &&
          current?['costSaved'] == true &&
          current?['remainingMl'] == '0' &&
          widget.scope.role == 'admin' &&
          !_busy &&
          snapshot.connectionState == ConnectionState.done;
      return BatchDetailPage.official(
        officialTitle: widget.initial['code'] as String,
        kloterCode: widget.kloterCode,
        officialReviewed: approved,
        officialCancelled: status == 'cancelled',
        officialData: current == null ? null : _data(current),
        officialNumber: widget.initial['wok_number'] as int,
        officialDocument: widget.onOpenPekerjaan,
        officialActions: current == null ? const [] : _actions(current),
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
            : const LinearProgressIndicator(),
        officialAction: current != null && (approved || canApprove)
            ? BatchReviewActions(
                batchNumber: current['wok_number'] as int,
                batchCode: widget.initial['code'] as String,
                label: approved ? 'Batch tervalidasi' : 'Validasi',
                verified: approved,
                onVerify: () =>
                    _run(() => widget.api.finishBatch(widget.scope, _id)),
              )
            : null,
        onNavigate: widget.onNavigate,
      );
    },
  );
}

enum _Input { text, integer, date, quantity, money }

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
  Future<Json> Function(List<String>) save,
) => showDialog<Json>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ProductionForm(title: title, fields: fields, save: save),
);

class _ProductionForm extends StatefulWidget {
  const _ProductionForm({
    required this.title,
    required this.fields,
    required this.save,
  });
  final String title;
  final List<_Field> fields;
  final Future<Json> Function(List<String>) save;

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
        _error = _errorText(error);
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
                for (final (i, field) in widget.fields.indexed)
                  TextFormField(
                    controller: _inputs[i],
                    enabled: _pending == null,
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.kind == _Input.date
                          ? 'YYYY-MM-DDTHH:MM'
                          : null,
                    ),
                    validator: (value) => _validate(value, field.kind),
                  ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? 'Menyimpan…'
                : _pending != null
                ? 'Coba lagi'
                : 'Simpan',
          ),
        ),
      ],
    ),
  );
}
