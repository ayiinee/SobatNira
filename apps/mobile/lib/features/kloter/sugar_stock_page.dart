import 'package:flutter/material.dart';
import '../pekerjaan/review_api.dart';
import 'batch_draft_page.dart';
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stok dan penelusuran produksi'),
          FutureBuilder<Json>(
            future: _data,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Text(
                  snapshot.hasError
                      ? 'Saldo belum tersedia. Buka stok untuk mencoba lagi.'
                      : 'Memuat saldo…',
                );
              }
              final stock = snapshot.requireData;
              final sources = (stock['sources'] as List).cast<Json>().where(
                (r) => widget.lotId == null || r['originLotId'] == widget.lotId,
              );
              BigInt total(String quality) => sources
                  .where((r) => r['quality'] == quality)
                  .fold(
                    BigInt.zero,
                    (a, r) =>
                        a + productionWeightUnits(r['onHandKg'] as String)!,
                  );
              final totals = stock['totals'] as Json?;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock['active'] == true
                        ? 'Gula baik: ${productionWeight(total('good'))} kg · Gula gagal: ${productionWeight(total('failed'))} kg'
                        : 'Saldo awal gula belum dicatat.',
                  ),
                  if (widget.lotId == null && totals != null)
                    Text(
                      'Stok tebu: ${totals['caneKg']} kg · Nira: ${millilitersToLiters(totals['juiceOnHandMl'] as String)} L',
                    ),
                  Text(stock['limitation'] as String),
                ],
              );
            },
          ),
          TextButton(
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
            child: const Text('Buka stok gula dan riwayat'),
          ),
        ],
      ),
    ),
  );
}

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
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
    ),
    body: FutureBuilder<List<Json>>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? TextButton(
                    onPressed: () => setState(() => _data = _load()),
                    child: Text(_errorText(snapshot.error!)),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final [state, history] = snapshot.requireData;
        final pending = widget.api.pendingInventory(widget.scope);
        final canEdit = _manage && !_busy && pending == null;
        final totals = state['totals'] as Json?;
        final sources = (state['sources'] as List).cast<Json>().where(
          (s) => widget.lotId == null || s['originLotId'] == widget.lotId,
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.scope.factoryName),
            Text(state['limitation'] as String),
            Text('Aktif sejak: ${state['activatedAt'] ?? 'Belum aktif'}'),
            if (totals != null) ...[
              Text(
                'Hasil produksi bruto sejak aktivasi: ${totals['grossWeightKg']} kg',
              ),
              Text('Gula lama terpakai: ${totals['reusedWeightKg']} kg'),
              Text(
                'Tambahan bersih rework dan produksi: ${totals['netAdditionalKg']} kg',
              ),
            ],
            if (_error != null) Text(_error!),
            if (pending != null) ...[
              Text(
                'Permintaan belum terkonfirmasi: ${(pending['body'] as Json)['requestId']}',
              ),
              Text('Alasan: ${(pending['body'] as Json)['reason']}'),
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
            if (state['active'] != true && canEdit)
              FilledButton(
                onPressed: () => _opening(state),
                child: const Text('Catat saldo awal'),
              ),
            for (final source in sources)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${source['gradeCode']} · ${source['quality'] == 'good' ? 'Gula baik' : 'Gula gagal'}',
                      ),
                      Text(
                        'Saldo ${source['onHandKg']} kg · Dipesan ${source['reservedKg']} kg · Tersedia ${source['availableKg']} kg',
                      ),
                      Text(
                        'Asal: ${source['lotCode'] ?? source['originLotId'] ?? 'Belum diketahui (saldo awal)'}',
                      ),
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
                          spacing: 8,
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
              ),
            const Text('Riwayat mutasi stok'),
            for (final row in (history['items'] as List).cast<Json>())
              ListTile(
                title: Text(
                  '${row['gradeCode']} · ${row['quantityDeltaKg']} kg · ${row['kind']}',
                ),
                subtitle: Text(
                  '${row['reason']}\n${row['createdAt']} · ${row['actorId']}',
                ),
              ),
            Row(
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
                  onPressed: (history['items'] as List).length < 20
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
