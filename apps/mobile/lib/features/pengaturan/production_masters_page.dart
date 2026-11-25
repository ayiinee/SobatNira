import 'package:flutter/material.dart';
import '../pekerjaan/review_api.dart';
import '../kloter/sugar_stock_page.dart';

class ProductionMastersPage extends StatefulWidget {
  const ProductionMastersPage({
    super.key,
    required this.api,
    required this.scope,
    required this.kind,
    this.synthetic = false,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String kind;
  final bool synthetic;
  @override
  State<ProductionMastersPage> createState() => _MastersState();
}

class _MastersState extends State<ProductionMastersPage> {
  late Future<Json> _data = _load();
  Json? _pending;
  bool _busy = false;
  String? _error;
  List<String> get _path => [...widget.scope.basePath, 'production', 'masters'];
  Future<Json> _load() => widget.api.getProduction(
    _path,
    query: {'history': 'true', 'synthetic': '${widget.synthetic}'},
  );
  Future<void> _save(Json body) async {
    setState(() {
      _busy = true;
      _pending = body;
      _error = null;
    });
    try {
      await widget.api.writeProduction(_path, body);
      _pending = null;
    } on ReviewApiError catch (error) {
      if (error.status == 400 || error.status == 409 || error.status == 403) {
        _pending = null;
      }
      _error = stockErrorText(error);
    } catch (error) {
      _error = stockErrorText(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _data = _load();
        });
      }
    }
  }

  Future<void> _edit(Json? row) async {
    final code = TextEditingController(text: row?['code'] as String?);
    final name = TextEditingController(text: row?['name'] as String?);
    final capacity = TextEditingController(
      text: row?['capacityLiters'] as String?,
    );
    final reason = TextEditingController();
    var active = row?['active'] as bool? ?? true;
    final result = await showDialog<Json>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(widget.kind == 'wok' ? 'Master wajan' : 'Master grade'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  enabled: row == null,
                  decoration: InputDecoration(
                    labelText: widget.kind == 'wok'
                        ? 'Nomor wajan'
                        : 'Kode grade',
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                if (widget.kind == 'wok')
                  TextField(
                    controller: capacity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Kapasitas (liter), informasi saja',
                    ),
                  ),
                SwitchListTile(
                  title: const Text('Aktif untuk pilihan baru'),
                  value: active,
                  onChanged: (value) => update(() => active = value),
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Alasan perubahan',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, {
                'requestId': ReviewApi.requestUuid(),
                'kind': widget.kind,
                'code': code.text.trim(),
                'name': name.text.trim(),
                'version': row?['version'] ?? 0,
                'active': active,
                'reason': reason.text,
                if (widget.kind == 'wok')
                  'capacityLiters': capacity.text.replaceAll(',', '.'),
              }),
              child: const Text('Simpan versi baru'),
            ),
          ],
        ),
      ),
    );
    // Dialog keeps controllers through its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in [code, name, capacity, reason]) {
      c.dispose();
    }
    if (result != null && mounted) {
      await _save(result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.kind == 'wok' ? 'Wajan produksi' : 'Grade produksi'),
    ),
    body: FutureBuilder<Json>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: Text(
              snapshot.hasError ? 'Master belum tersedia.' : 'Memuat master…',
            ),
          );
        }
        final rows = (snapshot.requireData['items'] as List)
            .cast<Json>()
            .where((r) => r['kind'] == widget.kind)
            .toList();
        final latest = <String, Json>{};
        for (final r in rows) {
          latest.putIfAbsent(r['code'] as String, () => r);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Perubahan berlaku untuk pilihan baru. Riwayat batch tetap memakai versi sebelumnya.',
            ),
            if (widget.kind == 'wok')
              const Text(
                'Kapasitas berupa informasi. Batas minimum dan campuran gula–nira belum ditetapkan.',
              ),
            if (_error != null) Text(_error!),
            if (_pending != null)
              FilledButton(
                onPressed: _busy ? null : () => _save(_pending!),
                child: const Text('Periksa ulang permintaan yang sama'),
              ),
            if (widget.scope.role == 'admin')
              FilledButton(
                onPressed: _busy || _pending != null ? null : () => _edit(null),
                child: const Text('Tambah master'),
              ),
            for (final r in latest.values)
              ListTile(
                title: Text('${r['code']} · ${r['name']}'),
                subtitle: Text(
                  'Versi ${r['version']} · ${r['active'] == true ? 'Aktif' : 'Nonaktif'}${widget.kind == 'wok' ? ' · ${r['capacityLiters']} L' : ''}',
                ),
                trailing: widget.scope.role == 'admin'
                    ? IconButton(
                        tooltip: 'Ubah master',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy || _pending != null
                            ? null
                            : () => _edit(r),
                      )
                    : null,
              ),
            if (widget.kind == 'wok') ...[
              const Text('Pemakaian batch fisik sah, dihitung sekali'),
              for (final u
                  in (snapshot.requireData['usage'] as List).cast<Json>())
                Text('Wajan ${u['wokNumber']}: ${u['batchCount']} batch'),
            ],
            const Divider(),
            const Text('Riwayat versi'),
            for (final r in rows)
              ListTile(
                title: Text('${r['code']} · versi ${r['version']}'),
                subtitle: Text(
                  '${r['name']} · ${r['reason']} · ${r['createdAt']}',
                ),
              ),
          ],
        );
      },
    ),
  );
}
