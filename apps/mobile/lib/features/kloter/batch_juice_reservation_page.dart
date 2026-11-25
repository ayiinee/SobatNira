import 'package:flutter/material.dart';

import '../pekerjaan/review_api.dart';
import 'juice_volume.dart';

class BatchJuiceReservationPage extends StatefulWidget {
  const BatchJuiceReservationPage({
    super.key,
    required this.api,
    required this.scope,
    required this.lotId,
    required this.batchId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;
  final String batchId;

  @override
  State<BatchJuiceReservationPage> createState() => _ReservationState();
}

class _ReservationState extends State<BatchJuiceReservationPage> {
  final _volume = TextEditingController();
  late Future<List<Json>> _data = _load();
  String? _origin;
  String? _error;
  bool _busy = false;

  Future<List<Json>> _load() async {
    final batch = await widget.api.factoryBatch(widget.scope, widget.batchId);
    final stock = await widget.api.juice(
      widget.scope,
      widget.lotId,
      synthetic: batch['is_synthetic'] == true,
    );
    final origins = (stock['origins'] as List).cast<Json>();
    for (final origin in origins) {
      final lot = await widget.api.lot(
        widget.scope,
        origin['originLotId'] as String,
        synthetic: batch['is_synthetic'] == true,
      );
      origin['label'] = lot['displayCode'] ?? origin['originLotId'];
    }
    return [batch, stock];
  }

  @override
  void dispose() {
    _volume.dispose();
    super.dispose();
  }

  Future<void> _submit(Json batch) async {
    final pending = widget.api.pendingReservation(widget.batchId);
    final ml =
        pending?['quantityMl'] as String? ?? litersToMilliliters(_volume.text);
    final origin = pending?['originLotId'] as String? ?? _origin;
    if (ml == null ||
        origin == null ||
        compareJuiceVolumes(ml, batch['remainingMl'] as String) > 0 &&
            pending == null) {
      setState(
        () => _error = 'Pilih asal dan volume positif sesuai sisa kebutuhan.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.reserveJuiceSource(
        widget.scope,
        widget.lotId,
        widget.batchId,
        originLotId: origin,
        quantityMl: ml,
        synthetic: batch['is_synthetic'] == true,
      );
      _volume.clear();
    } catch (error) {
      _error = error is ReviewApiError
          ? error.detail ?? error.message
          : 'Hasil belum terkonfirmasi. Coba lagi permintaan yang sama.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _data = _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reservasi nira'),
      actions: [
        IconButton(
          onPressed: _busy ? null : () => setState(() => _data = _load()),
          icon: const Icon(Icons.refresh),
          tooltip: 'Muat ulang saldo',
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
                    child: const Text('Coba lagi memuat saldo'),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final [batch, stock] = snapshot.requireData;
        final pending = widget.api.pendingReservation(widget.batchId);
        final origins = (stock['origins'] as List)
            .cast<Json>()
            .where(
              (row) =>
                  compareJuiceVolumes(row['availableMl'] as String, '0') > 0,
            )
            .toList();
        final selected = origins.any((row) => row['originLotId'] == _origin)
            ? _origin
            : null;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Sisa kebutuhan: ${millilitersToLiters(batch['remainingMl'] as String)} L',
            ),
            for (final row
                in (batch['reservations'] as List? ?? const []).cast<Json>())
              ListTile(
                title: Text(
                  '${row['lotCode']} · ${millilitersToLiters(row['quantityMl'] as String)} L',
                ),
                subtitle: Text('${row['state']} · ${row['requestId']}'),
              ),
            const Text(
              'Sumber harus sudah berada pada kloter memasak. Gunakan Transfer nira untuk menambah sumber.',
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (pending != null) ...[
              Text('Permintaan belum terkonfirmasi: ${pending['requestId']}'),
              FilledButton(
                onPressed: _busy ? null : () => _submit(batch),
                child: const Text('Coba lagi reservasi yang sama'),
              ),
            ] else if (batch['status'] == 'draft' &&
                batch['lotClosed'] != true &&
                batch['remainingMl'] != '0') ...[
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Asal nira'),
                items: [
                  for (final row in origins)
                    DropdownMenuItem(
                      value: row['originLotId'] as String,
                      child: Text(
                        '${row['label']} · ${millilitersToLiters(row['availableMl'] as String)} L',
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _origin = value),
              ),
              TextField(
                controller: _volume,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Volume nira (L)'),
              ),
              FilledButton(
                onPressed: _busy || origins.isEmpty
                    ? null
                    : () => _submit(batch),
                child: const Text('Tambah reservasi'),
              ),
              if (origins.isEmpty)
                const Text(
                  'Saldo tersedia tidak cukup. Transfer nira terlebih dahulu.',
                ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (batch['remainingMl'] == '0')
              const Text('Reservasi lengkap. Kembali untuk mengesahkan batch.'),
          ],
        );
      },
    ),
  );
}
