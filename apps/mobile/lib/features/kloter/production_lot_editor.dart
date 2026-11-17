import 'package:flutter/material.dart';

import '../pekerjaan/review_api.dart';
import 'production_catalog_page.dart';

class ProductionLotEditor extends StatefulWidget {
  const ProductionLotEditor({
    super.key,
    required this.api,
    required this.scope,
    this.lot,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final Json? lot;

  @override
  State<ProductionLotEditor> createState() => _ProductionLotEditorState();
}

class _ProductionLotEditorState extends State<ProductionLotEditor> {
  late final _code = TextEditingController(
    text: widget.lot?['displayCode'] as String?,
  );
  late String? _supplierId = widget.lot?['supplierId'] as String?;
  late String? _supplierName = widget.lot?['supplierName'] as String?;
  late DateTime _receivedAt = widget.lot == null
      ? DateTime.now()
      : DateTime.parse(widget.lot!['receivedAt'] as String).toLocal();
  bool _saving = false;
  String? _error;
  bool get _official => widget.lot?['intake'] != null;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _supplier() async {
    final chosen = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        builder: (_) => ProductionCatalogPage(
          api: widget.api,
          scope: widget.scope,
          kind: ProductionCatalog.suppliers,
          selectSupplier: true,
        ),
      ),
    );
    if (mounted && chosen != null) {
      setState(() {
        _supplierId = chosen['id'] as String;
        _supplierName = chosen['name'] as String;
      });
    }
  }

  Future<void> _pickTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _receivedAt,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_receivedAt),
    );
    if (mounted && time != null) {
      setState(
        () => _receivedAt = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_supplierId == null) {
      setState(() => _error = 'Pilih pemasok aktif.');
      return;
    }
    final previous = widget.lot;
    final code = _code.text.trim();
    final values = <String, dynamic>{
      if (previous == null || code != (previous['displayCode'] ?? ''))
        'displayCode': code.isEmpty ? null : code,
      if (!_official &&
          (previous == null || _supplierId != previous['supplierId']))
        'supplierId': _supplierId,
      if (!_official &&
          (previous == null ||
              !_receivedAt.isAtSameMomentAs(
                DateTime.parse(previous['receivedAt'] as String),
              )))
        'receivedAt': DateTime.fromMillisecondsSinceEpoch(
          _receivedAt.millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
    };
    if (values.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveLot(
        widget.scope,
        values,
        id: previous?['id'] as String?,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ReviewApiError
              ? switch (error.status) {
                  409 =>
                    'Penerimaan kloter sudah disahkan. Muat ulang detail dan gunakan koreksi nota untuk data penerimaan.',
                  400 || 404 =>
                    'Pemasok atau kloter tidak tersedia. Muat ulang detail atau pilih pemasok aktif kembali.',
                  _ => error.message,
                }
              : 'Penyimpanan belum terkonfirmasi. Kembali dan muat ulang daftar sebelum mencoba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = MaterialLocalizations.of(context);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.lot == null ? 'Tambah kloter' : 'Edit kloter'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.scope.factoryName),
              TextField(
                controller: _code,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Kode kloter (opsional)',
                ),
              ),
              ListTile(
                title: const Text('Pemasok'),
                subtitle: Text(_supplierName ?? 'Pilih pemasok aktif'),
                trailing: _official
                    ? const Icon(Icons.lock_outline)
                    : const Icon(Icons.chevron_right),
                onTap: _official || _saving ? null : _supplier,
              ),
              ListTile(
                title: const Text('Waktu penerimaan'),
                subtitle: Text(
                  '${labels.formatFullDate(_receivedAt)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(_receivedAt))} (waktu perangkat)',
                ),
                trailing: Icon(
                  _official
                      ? Icons.lock_outline
                      : Icons.calendar_today_outlined,
                ),
                onTap: _official || _saving ? null : _pickTime,
              ),
              if (_official)
                const Text(
                  'Penerimaan sudah disahkan. Perubahan pemasok dan waktu memerlukan koreksi nota.',
                ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Simpan kloter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
