import 'package:flutter/material.dart';
import '../pekerjaan/review_api.dart';
import 'juice_volume.dart';

BigInt? productionWeightUnits(String value) {
  if (!RegExp(r'^(0|[1-9]\d*)([.,]\d{1,6})?$').hasMatch(value) ||
      value.length > 64) {
    return null;
  }
  final parts = value.replaceAll(',', '.').split('.');
  return BigInt.parse(
    parts.first + (parts.length == 1 ? '' : parts.last).padRight(6, '0'),
  );
}

String productionWeight(BigInt value) {
  final digits = value.abs().toString().padLeft(7, '0');
  final text =
      '${digits.substring(0, digits.length - 6)}.${digits.substring(digits.length - 6)}'
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  return '${value.isNegative ? '-' : ''}$text';
}

class BatchDraftPage extends StatefulWidget {
  const BatchDraftPage({
    super.key,
    required this.api,
    required this.scope,
    required this.lotId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;
  @override
  State<BatchDraftPage> createState() => _BatchDraftState();
}

class _BatchDraftState extends State<BatchDraftPage> {
  final _id = ReviewApi.requestUuid();
  final _code = TextEditingController();
  final _wok = TextEditingController();
  final _time = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 16),
  );
  final _liters = TextEditingController();
  final _physical = TextEditingController();
  final _grades = <List<TextEditingController>>[];
  late final Future<Json> _sources = widget.api.batchSources(
    widget.scope,
    widget.lotId,
  );
  late final Future<Json> _stock = widget.api.sugarStock(widget.scope);
  String _kind = 'normal';
  List<Json> _masters = [];
  late final Future<Json> _masterData = widget.api
      .getProduction([...widget.scope.basePath, 'production', 'masters'])
      .then((data) {
        _masters = (data['items'] as List)
            .cast<Json>()
            .where((r) => r['active'] == true)
            .toList();
        return data;
      });
  Json? _source;
  String? _error;
  bool _busy = false;
  Json? _pending;

  @override
  void initState() {
    super.initState();
    _addGrade();
  }

  void _addGrade() =>
      _grades.add(List.generate(3, (_) => TextEditingController()));
  @override
  void dispose() {
    for (final c in [
      _code,
      _wok,
      _time,
      _liters,
      _physical,
      ..._grades.expand((r) => r),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      enabled: !_busy && _pending == null,
      onChanged: (_) => setState(() {}),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    ),
  );

  void _prefill(Json? candidate) {
    setState(() {
      _source = candidate;
      if (candidate == null) return;
      _wok.text = '${candidate['wokNumber'] ?? ''}';
      _physical.text = '${candidate['physicalWeightKg'] ?? ''}';
      _grades.first[0].text = '${candidate['grade'] ?? ''}';
      _grades.first[1].text = _physical.text;
      final finish = candidate['finishTime'];
      if (finish is String &&
          DateTime.tryParse(finish) != null &&
          finish.contains('T')) {
        _time.text = finish;
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final volume = litersToMilliliters(_liters.text);
      final wok = int.tryParse(_wok.text);
      final time = DateTime.tryParse(_time.text);
      if (volume == null || wok == null || time == null) {
        throw const FormatException();
      }
      _pending ??= {
        'id': _id,
        'kind': _kind,
        'lotId': widget.lotId,
        'code': _code.text.trim(),
        'wokNumber': wok,
        'occurredAt': time.toUtc().toIso8601String(),
        'quantityMl': volume,
        'physicalWeightKg': _physical.text.replaceAll(',', '.'),
        'grades': [
          for (final g in _grades)
            {
              'code': g[0].text.trim(),
              'weightKg': g[1].text.replaceAll(',', '.'),
              'pricePerKgRupiah': g[2].text,
            },
        ],
        if (_source != null) 'source': _source!['source'],
        if (_masters.any((r) => r['kind'] == 'wok' && r['code'] == _wok.text) &&
            _grades.every(
              (g) => _masters.any(
                (r) => r['kind'] == 'grade' && r['code'] == g[0].text,
              ),
            ))
          'masterReferences': {
            'wok': {
              for (final r in _masters.where(
                (r) => r['kind'] == 'wok' && r['code'] == _wok.text,
              )) ...{'code': r['code'], 'version': r['version']},
            },
            'grades': [
              for (final g in _grades)
                for (final r in _masters.where(
                  (r) => r['kind'] == 'grade' && r['code'] == g[0].text,
                ))
                  {'code': r['code'], 'version': r['version']},
            ],
          },
      };
      final result = await widget.api.createBatch(widget.scope, _pending!);
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (error is ReviewApiError &&
          (error.status == 400 || error.status == 409)) {
        _pending = null;
      }
      if (mounted) {
        setState(
          () => _error = error is ReviewApiError
              ? error.detail ?? error.message
              : error is FormatException
              ? 'Periksa waktu, nomor wajan, dan volume nira.'
              : 'Hasil belum terkonfirmasi. Coba lagi draf yang sama.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weights = _grades
        .map((g) => productionWeightUnits(g[1].text))
        .toList();
    final total = weights.any((w) => w == null)
        ? null
        : weights.fold(BigInt.zero, (a, b) => a + b!);
    final physical = productionWeightUnits(_physical.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah batch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<Json>(
            future: _sources,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Sumber nota belum tersedia. Draf manual tetap bisa dicatat.',
                );
              }
              final rows = (snapshot.data?['items'] as List? ?? const [])
                  .cast<Json>()
                  .where((r) => r['batchId'] == null)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Isi awal dari nota sah (opsional)'),
                  for (final row in rows)
                    TextButton(
                      onPressed: _busy || _pending != null
                          ? null
                          : () => _prefill(row),
                      child: Text(
                        '${(row['source'] as Json)['block']} · ${(row['source'] as Json)['rowReference']} · Wajan ${row['wokNumber']}',
                      ),
                    ),
                  if (_source != null) Text('Sumber: ${_source!['source']}'),
                ],
              );
            },
          ),
          FutureBuilder<Json>(
            future: _stock,
            builder: (context, snapshot) => Column(
              children: [
                if (snapshot.data?['reworkEnabled'] == true)
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Jenis batch'),
                    items: const [
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text('Produksi biasa'),
                      ),
                      DropdownMenuItem(
                        value: 'rework',
                        child: Text('Rework dengan nira baru'),
                      ),
                    ],
                    onChanged: _busy || _pending != null
                        ? null
                        : (v) => setState(() => _kind = v!),
                  )
                else
                  const Text(
                    'Rework belum diaktifkan setelah integrasi laporan.',
                  ),
              ],
            ),
          ),
          FutureBuilder<Json>(
            future: _masterData,
            builder: (context, snapshot) => Column(
              children: [
                if (snapshot.hasError)
                  const Text(
                    'Pilihan master belum tersedia. Kode manual tetap diterima.',
                  ),
                if (snapshot.hasData) ...[
                  const Text('Pilihan master aktif (opsional)'),
                  Wrap(
                    children: [
                      for (final r in _masters.where((r) => r['kind'] == 'wok'))
                        TextButton(
                          onPressed: _busy || _pending != null
                              ? null
                              : () => setState(
                                  () => _wok.text = r['code'] as String,
                                ),
                          child: Text(
                            'Wajan ${r['code']} \u00b7 ${r['name']} \u00b7 ${r['capacityLiters']} L',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _field('Kode batch', _code),
          _field('Nomor wajan', _wok, number: true),
          _field('Waktu pemasakan', _time),
          _field('Volume nira (L)', _liters, number: true),
          const Text(
            'Volume nira diisi manual. ISI dan HASIL pada nota tetap kg.',
          ),
          _field('Hasil fisik (kg)', _physical, number: true),
          for (final (index, g) in _grades.indexed) ...[
            Text('Grade ${index + 1}'),
            _field('Kode grade ${index + 1}', g[0]),
            Wrap(
              children: [
                for (final r in _masters.where((r) => r['kind'] == 'grade'))
                  TextButton(
                    onPressed: _busy || _pending != null
                        ? null
                        : () => setState(() => g[0].text = r['code'] as String),
                    child: Text('${r['code']} \u00b7 ${r['name']}'),
                  ),
              ],
            ),
            _field('Berat grade ${index + 1} (kg)', g[1], number: true),
            _field('Harga grade ${index + 1} per kg (Rp)', g[2], number: true),
          ],
          if (_grades.length < 100)
            TextButton(
              onPressed: _busy || _pending != null
                  ? null
                  : () => setState(_addGrade),
              child: const Text('Tambah grade'),
            ),
          Text(
            'Total grade: ${total == null ? 'Periksa isian' : productionWeight(total)} kg',
          ),
          Text(
            'Selisih dari berat fisik: ${total == null || physical == null ? 'Periksa isian' : productionWeight(total - physical)} kg',
          ),
          if (_error != null) Text(_error!),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _pending == null ? 'Simpan draf' : 'Coba lagi draf yang sama',
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
