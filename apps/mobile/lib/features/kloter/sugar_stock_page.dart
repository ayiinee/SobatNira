import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/adaptive_value.dart';
import '../../widgets/nira_loading.dart';
import '../../widgets/page_frame.dart';
import '../laporan/connected_reports.dart';
import '../pekerjaan/review_api.dart';
import '../pengaturan/settings_widgets.dart';
import 'batch_draft_page.dart';
import 'demo_production.dart';
import 'juice_volume.dart';

String stockErrorText(Object error) => error is ReviewApiError
    ? error.detail ?? error.message
    : 'Hasil belum terkonfirmasi. Coba lagi permintaan yang sama.';

class SugarStockCard extends StatefulWidget {
  const SugarStockCard({
    super.key,
    required this.api,
    required this.scope,
    this.synthetic = false,
    this.lotId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final bool synthetic;
  final String? lotId;
  @override
  State<SugarStockCard> createState() => _StockCardState();
}

class _StockCardState extends State<SugarStockCard> {
  late Future<Json> _data = widget.api.sugarStock(
    widget.scope,
    synthetic: widget.synthetic,
  );
  @override
  void didUpdateWidget(covariant SugarStockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.synthetic != widget.synthetic ||
        oldWidget.scope.factoryId != widget.scope.factoryId) {
      _data = widget.api.sugarStock(widget.scope, synthetic: widget.synthetic);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NiraSpace.md,
      children: [
        const SettingsInfoRow(
          icon: Icons.inventory_2_outlined,
          title: 'Stok dan penelusuran produksi',
        ),
        FutureBuilder<Json>(
          future: _data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return snapshot.hasError
                  ? const SettingsMessage(
                      icon: Icons.info_outline,
                      message:
                          'Saldo belum tersedia. Buka stok untuk mencoba lagi.',
                    )
                  : const NiraLoading(label: 'Memuat saldo…', compact: true);
            }
            final stock = snapshot.requireData;
            final sources = (stock['sources'] as List).cast<Json>().where(
              (r) => widget.lotId == null || r['originLotId'] == widget.lotId,
            );
            BigInt total(String quality) => sources
                .where((r) => r['quality'] == quality)
                .fold(
                  BigInt.zero,
                  (a, r) => a + productionWeightUnits(r['onHandKg'] as String)!,
                );
            final totals = stock['totals'] as Json?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: NiraSpace.md,
              children: [
                if (stock['active'] == true)
                  Row(
                    spacing: NiraSpace.sm,
                    children: [
                      Expanded(
                        child: _StockMetric(
                          'Gula baik',
                          _kg(productionWeight(total('good'))),
                        ),
                      ),
                      Expanded(
                        child: _StockMetric(
                          'Gula gagal',
                          _kg(productionWeight(total('failed'))),
                        ),
                      ),
                    ],
                  )
                else
                  const SettingsMessage(
                    icon: Icons.info_outline,
                    message: 'Saldo awal gula belum dicatat.',
                    pending: true,
                  ),
                if (widget.lotId == null && totals != null)
                  Row(
                    spacing: NiraSpace.sm,
                    children: [
                      Expanded(
                        child: _StockMetric('Stok tebu', _kg(totals['caneKg'])),
                      ),
                      Expanded(
                        child: _StockMetric(
                          'Stok nira',
                          '${reportNumber(millilitersToLiters(totals['juiceOnHandMl'] as String))} L',
                        ),
                      ),
                    ],
                  ),
                Text(
                  stock['limitation'] as String,
                  style: niraText(NiraType.body, color: niraLeaf),
                ),
              ],
            );
          },
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SugarStockPage(
                  api: widget.api,
                  scope: widget.scope,
                  synthetic: widget.synthetic,
                  lotId: widget.lotId,
                ),
              ),
            );
            if (mounted) {
              setState(
                () => _data = widget.api.sugarStock(
                  widget.scope,
                  synthetic: widget.synthetic,
                ),
              );
            }
          },
          label: const Text('Buka stok gula dan riwayat'),
          icon: const Icon(Icons.arrow_forward, size: 18),
          iconAlignment: IconAlignment.end,
        ),
      ],
    ),
  );
}

String _kg(Object? value) => value == null ? '—' : '${reportNumber(value)} kg';

class _StockMetric extends StatelessWidget {
  const _StockMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: niraGreen.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(NiraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NiraSpace.xs,
        children: [
          Text(label, style: niraText(NiraType.caption, color: niraLeaf)),
          NiraValue(
            value,
            label: label,
            style: niraText(NiraType.title, weight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _StockHeading extends StatelessWidget {
  const _StockHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    headingLevel: 2,
    child: Text(
      title,
      style: niraText(NiraType.section, weight: FontWeight.w700),
    ),
  );
}

class _StockAmount extends StatelessWidget {
  const _StockAmount(this.label, this.value);

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Row(
    spacing: NiraSpace.md,
    children: [
      Expanded(flex: 2, child: Text(label, style: niraText(NiraType.body))),
      Expanded(
        child: NiraValue(
          _kg(value),
          label: label,
          alignment: Alignment.centerRight,
          style: niraText(NiraType.body, weight: FontWeight.w700),
        ),
      ),
    ],
  );
}

String _stockDate(BuildContext context, Object? value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  if (date == null) return 'Waktu tidak tersedia';
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true);
  return '${formatDate(date)} · $time';
}

String _movementLabel(Object? kind) => switch (kind) {
  'opening' => 'Saldo awal',
  'production' => 'Hasil produksi',
  'correction' => 'Koreksi produksi',
  'adjustment' => 'Penyesuaian stok',
  'quality' => 'Perubahan kualitas',
  'rework' => 'Masak ulang',
  _ => 'Mutasi stok',
};

class SugarStockPage extends StatefulWidget {
  const SugarStockPage({
    super.key,
    required this.api,
    required this.scope,
    this.synthetic = false,
    this.lotId,
    this.reworkBatchId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final bool synthetic;
  final String? lotId;
  final String? reworkBatchId;
  @override
  State<SugarStockPage> createState() => _SugarStockState();
}

class _SugarStockState extends State<SugarStockPage> {
  late Future<List<Json>> _data = _load();
  int _offset = 0;
  bool _busy = false;
  String? _error;
  List<String> get _base => [...widget.scope.basePath, 'production', 'sugar'];
  bool get _manage => widget.scope.role == 'admin' && !widget.synthetic;
  Future<List<Json>> _load() => Future.wait([
    widget.api.sugarStock(widget.scope, synthetic: widget.synthetic),
    widget.api.getProduction(
      [..._base, 'history'],
      query: {
        'synthetic': '${widget.synthetic}',
        'limit': '20',
        'offset': '$_offset',
      },
    ),
  ]);

  Future<void> _send(List<String> path, Json body) async {
    setState(() => _busy = true);
    try {
      await widget.api.inventoryCommand(widget.scope, path, body);
      _error = null;
    } catch (error) {
      _error = _errorText(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _data = _load();
        });
      }
    }
  }

  String _errorText(Object error) => stockErrorText(error);

  Future<void> _opening(Json state) async {
    final rows = <List<TextEditingController>>[
      List.generate(2, (_) => TextEditingController()),
    ];
    final qualities = <String>['good'];
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Saldo awal hasil hitung fisik'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Catat stok yang ada sekarang. Riwayat lama tidak dijumlahkan ulang. Asal batch yang belum diketahui akan ditandai.',
                  ),
                  for (final (index, row) in rows.indexed) ...[
                    TextField(
                      controller: row[0],
                      decoration: InputDecoration(
                        labelText: 'Kode grade ${index + 1}',
                      ),
                    ),
                    TextField(
                      controller: row[1],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Berat fisik (kg)',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: qualities[index],
                      items: const [
                        DropdownMenuItem(
                          value: 'good',
                          child: Text('Gula baik'),
                        ),
                        DropdownMenuItem(
                          value: 'failed',
                          child: Text('Gula gagal'),
                        ),
                      ],
                      onChanged: (v) => qualities[index] = v!,
                    ),
                  ],
                  TextButton(
                    onPressed: rows.length >= 100
                        ? null
                        : () => update(() {
                            rows.add(
                              List.generate(2, (_) => TextEditingController()),
                            );
                            qualities.add('good');
                          }),
                    child: const Text('Tambah sumber stok'),
                  ),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Alasan / catatan hitung fisik',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Catat saldo awal'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _send(
        [..._base, 'opening'],
        {
          'version': state['version'],
          'synthetic': widget.synthetic,
          'reason': reason.text,
          'items': [
            for (final (index, row) in rows.indexed)
              {
                'gradeCode': row[0].text,
                'quality': qualities[index],
                'weightKg': row[1].text.replaceAll(',', '.'),
              },
          ],
        },
      );
    }
    for (final c in [...rows.expand((r) => r), reason]) {
      c.dispose();
    }
  }

  Future<void> _change(Json state, Json source, String action) async {
    final amount = TextEditingController(), reason = TextEditingController();
    var direction = 'add';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(
            action == 'rework'
                ? 'Pesan gula untuk rework'
                : action == 'quality'
                ? 'Ubah kualitas stok'
                : 'Penyesuaian stok',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${source['gradeCode']} · ${source['quality']} · Tersedia ${source['availableKg']} kg',
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Berat (kg)'),
              ),
              if (action == 'adjustments')
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  items: const [
                    DropdownMenuItem(value: 'add', child: Text('Tambah')),
                    DropdownMenuItem(value: 'subtract', child: Text('Kurangi')),
                  ],
                  onChanged: (v) => update(() => direction = v!),
                ),
              if (action == 'quality')
                Text(
                  source['quality'] == 'good'
                      ? 'Pindahkan ke gula gagal'
                      : 'Pindahkan ke gula baik',
                ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Alasan'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _send(
        action == 'rework'
            ? [
                ...widget.scope.basePath,
                'production',
                'batches',
                widget.reworkBatchId!,
                'rework-inputs',
              ]
            : [..._base, action],
        {
          'version': state['version'],
          'synthetic': widget.synthetic,
          'reason': reason.text,
          'sourceId': source['id'],
          'weightKg': amount.text.replaceAll(',', '.'),
          if (action == 'adjustments') 'direction': direction,
          if (action == 'quality')
            'quality': source['quality'] == 'good' ? 'failed' : 'good',
        },
      );
    }
    amount.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => NiraPageScaffold(
    title: Text(
      widget.reworkBatchId == null
          ? 'Stok gula dan riwayat'
          : 'Gula sumber rework',
    ),
    actions: [
      IconButton(
        onPressed: _busy ? null : () => setState(() => _data = _load()),
        icon: const Icon(Icons.refresh),
        tooltip: 'Muat ulang stok',
      ),
    ],
    body: FutureBuilder<List<Json>>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: niraPageInset(context),
                    ),
                    child: SettingsLoadError(
                      accessDenied: switch (snapshot.error) {
                        ReviewApiError(status: 403) => true,
                        _ => false,
                      },
                      message: _errorText(snapshot.error!),
                      onRetry: () => setState(() => _data = _load()),
                    ),
                  )
                : const NiraLoading(label: 'Memuat stok gula…'),
          );
        }
        final [state, history] = snapshot.requireData;
        final pending = widget.api.pendingInventory(widget.scope);
        final canEdit = _manage && !_busy && pending == null;
        final active = state['active'] == true;
        final totals = state['totals'] as Json?;
        final movements = (history['items'] as List).cast<Json>();
        final sources = (state['sources'] as List).cast<Json>().where(
          (s) => widget.lotId == null || s['originLotId'] == widget.lotId,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            niraPageInset(context),
            NiraSpace.md,
            niraPageInset(context),
            NiraSpace.xl,
          ),
          children: [
            SettingsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: NiraSpace.md,
                children: [
                  SettingsInfoRow(
                    icon: Icons.factory_outlined,
                    title: widget.scope.factoryName,
                    description: active
                        ? 'Stok aktif sejak ${_stockDate(context, state['activatedAt'])}'
                        : 'Saldo awal gula belum dicatat.',
                  ),
                  const Divider(height: 1, color: niraLine),
                  Text(
                    state['limitation'] as String,
                    style: niraText(NiraType.body, color: niraLeaf),
                  ),
                ],
              ),
            ),
            if (totals != null) ...[
              const SizedBox(height: NiraSpace.lg),
              const _StockHeading('Ringkasan sejak aktivasi'),
              const SizedBox(height: NiraSpace.sm),
              SettingsPanel(
                child: Column(
                  spacing: NiraSpace.md,
                  children: [
                    _StockAmount(
                      'Hasil produksi bruto',
                      totals['grossWeightKg'],
                    ),
                    _StockAmount(
                      'Gula lama terpakai',
                      totals['reusedWeightKg'],
                    ),
                    const Divider(height: 1, color: niraLine),
                    _StockAmount('Tambahan bersih', totals['netAdditionalKg']),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tambahan bersih berasal dari produksi dan rework.',
                        style: niraText(NiraType.caption, color: niraLeaf),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: NiraSpace.lg),
              SettingsMessage(
                icon: Icons.info_outline,
                message: _error!,
                pending: true,
              ),
            ],
            if (pending != null) ...[
              const SizedBox(height: NiraSpace.lg),
              SettingsMessage(
                icon: Icons.schedule_outlined,
                title: 'Permintaan belum terkonfirmasi',
                message:
                    '${(pending['body'] as Json)['reason']}\nID permintaan ${(pending['body'] as Json)['requestId']}',
                pending: true,
              ),
              const SizedBox(height: NiraSpace.md),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _send(
                        (pending['path'] as List).cast<String>(),
                        pending['body'] as Json,
                      ),
                child: const Text('Coba lagi permintaan yang sama'),
              ),
            ],
            if (!active && canEdit) ...[
              const SizedBox(height: NiraSpace.lg),
              FilledButton.icon(
                onPressed: () => _opening(state),
                icon: const Icon(Icons.add),
                label: const Text('Catat saldo awal'),
              ),
            ],
            if (active || sources.isNotEmpty) ...[
              const SizedBox(height: NiraSpace.xl),
              const _StockHeading('Sumber gula'),
              const SizedBox(height: NiraSpace.sm),
              if (sources.isEmpty)
                const SettingsMessage(
                  icon: Icons.inventory_2_outlined,
                  message: 'Belum ada sumber gula untuk ditampilkan.',
                ),
              for (final source in sources) ...[
                SettingsPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: NiraSpace.md,
                    children: [
                      SettingsInfoRow(
                        icon: Icons.inventory_2_outlined,
                        title:
                            '${source['gradeCode']} · ${source['quality'] == 'good' ? 'Gula baik' : 'Gula gagal'}',
                        description:
                            'Asal: ${source['lotCode'] ?? source['originLotId'] ?? 'Belum diketahui (saldo awal)'}',
                      ),
                      const Divider(height: 1, color: niraLine),
                      _StockAmount('Tersedia', source['availableKg']),
                      _StockAmount('Saldo', source['onHandKg']),
                      _StockAmount('Dipesan', source['reservedKg']),
                      if (source['batchId'] != null)
                        TextButton(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => BatchTracePage(
                                api: widget.api,
                                scope: widget.scope,
                                batchId: source['batchId'] as String,
                              ),
                            ),
                          ),
                          child: const Text('Telusuri batch sumber'),
                        ),
                      if (canEdit)
                        Wrap(
                          spacing: NiraSpace.sm,
                          runSpacing: NiraSpace.sm,
                          children: [
                            if (widget.reworkBatchId != null)
                              TextButton(
                                onPressed: () =>
                                    _change(state, source, 'rework'),
                                child: const Text('Pesan untuk rework'),
                              )
                            else ...[
                              TextButton(
                                onPressed: () =>
                                    _change(state, source, 'adjustments'),
                                child: const Text('Sesuaikan stok'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _change(state, source, 'quality'),
                                child: const Text('Ubah kualitas'),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: NiraSpace.md),
              ],
            ],
            const SizedBox(height: NiraSpace.xl),
            const _StockHeading('Riwayat mutasi stok'),
            const SizedBox(height: NiraSpace.sm),
            if (movements.isEmpty)
              const SettingsMessage(
                icon: Icons.history,
                message: 'Belum ada mutasi stok untuk ditampilkan.',
              ),
            for (final row in movements) ...[
              SettingsPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: NiraSpace.sm,
                  children: [
                    _StockAmount(
                      _movementLabel(row['kind']),
                      row['quantityDeltaKg'],
                    ),
                    Text(
                      'Grade ${row['gradeCode']} · ${_stockDate(context, row['createdAt'])}',
                      style: niraText(NiraType.body, color: niraLeaf),
                    ),
                    Text(
                      row['reason'] as String,
                      style: niraText(NiraType.body),
                    ),
                    Text(
                      'ID akun ${row['actorId']}',
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NiraSpace.sm),
            ],
            if (_offset > 0 || movements.length >= 20)
              Wrap(
                spacing: NiraSpace.sm,
                runSpacing: NiraSpace.sm,
                children: [
                  TextButton(
                    onPressed: _offset == 0
                        ? null
                        : () => setState(() {
                            _offset -= 20;
                            _data = _load();
                          }),
                    child: const Text('Sebelumnya'),
                  ),
                  TextButton(
                    onPressed: movements.length < 20
                        ? null
                        : () => setState(() {
                            _offset += 20;
                            _data = _load();
                          }),
                    child: const Text('Berikutnya'),
                  ),
                ],
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        );
      },
    ),
  );
}

class BatchTracePage extends StatefulWidget {
  const BatchTracePage({
    super.key,
    required this.api,
    required this.scope,
    required this.batchId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String batchId;
  @override
  State<BatchTracePage> createState() => _TraceState();
}

class _TraceState extends State<BatchTracePage> {
  late Future<Json> _data = widget.api.batchTrace(widget.scope, widget.batchId);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Penelusuran batch')),
    body: FutureBuilder<Json>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? TextButton(
                    onPressed: () => setState(
                      () => _data = widget.api.batchTrace(
                        widget.scope,
                        widget.batchId,
                      ),
                    ),
                    child: Text(stockErrorText(snapshot.error!)),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final row = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SelectableText(
              'Batch ${row['batchId']} · ${row['kind']} · ${row['status']}',
            ),
            Text('Hasil fisik bruto: ${row['grossWeightKg']} kg'),
            Text('Gula lama terpakai: ${row['reusedWeightKg']} kg'),
            Text('Tambahan bersih: ${row['netAdditionalKg']} kg'),
            if (row['source'] != null)
              SelectableText('Nota sumber: ${row['source']}'),
            if (row['masterReferences'] != null)
              SelectableText('Versi master: ${row['masterReferences']}'),
            const Text('Asal nira'),
            for (final juice
                in (row['juice'] as List? ?? const []).cast<Json>())
              Text(
                '${juice['lotCode'] ?? juice['originLotId']}: ${millilitersToLiters(juice['quantityMl'] as String)} L · ${juice['state']}',
              ),
            const Text('Riwayat koreksi hasil'),
            for (final correction
                in (row['corrections'] as List? ?? const []).cast<Json>())
              ListTile(
                title: Text(
                  '${correction['reason']} · ${correction['status']}',
                ),
                subtitle: SelectableText(
                  'Sebelum: ${correction['before']}\nSesudah: ${correction['after']}\n${correction['updatedAt']}',
                ),
              ),
            if (row['financialStatus'] == 'REWORK_FINANCIALS_PENDING')
              const Text(
                'Nilai dan margin belum tersedia karena rework. Snapshot historis tetap tersimpan.',
              ),
            const Text('Gula sumber'),
            for (final source in (row['inputs'] as List).cast<Json>())
              ListTile(
                title: Text(
                  '${source['weightKg']} kg · ${source['gradeCode']} · ${source['state']}',
                ),
                subtitle: Text(
                  'Batch: ${source['sourceBatchId'] ?? 'Saldo awal; asal batch belum diketahui'}',
                ),
                onTap: source['sourceBatchId'] == null
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => BatchTracePage(
                            api: widget.api,
                            scope: widget.scope,
                            batchId: source['sourceBatchId'] as String,
                          ),
                        ),
                      ),
              ),
            const Text('Batch penerima'),
            for (final receiver in (row['recipients'] as List).cast<Json>())
              ListTile(
                title: Text(
                  '${receiver['weightKg']} kg · ${receiver['state']}',
                ),
                subtitle: Text(receiver['batchId'] as String),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => BatchTracePage(
                      api: widget.api,
                      scope: widget.scope,
                      batchId: receiver['batchId'] as String,
                    ),
                  ),
                ),
              ),
            const Text('Riwayat alokasi hasil'),
            for (final allocation in (row['allocations'] as List).cast<Json>())
              Text(
                'Versi ${allocation['version']} · ${allocation['originLotId']} · ${allocation['gradeCode']} · ${allocation['weightKg']} kg',
              ),
          ],
        );
      },
    ),
  );
}
