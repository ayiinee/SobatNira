import 'package:flutter/material.dart';

import 'review_api.dart';

class ManualNoteForm extends StatefulWidget {
  const ManualNoteForm({
    required this.document,
    required this.saving,
    required this.onSave,
    super.key,
  });
  final String document;
  final bool saving;
  final ValueChanged<Json> onSave;

  @override
  State<ManualNoteForm> createState() => _ManualNoteFormState();
}

class _ManualNoteFormState extends State<ManualNoteForm> {
  final _form = GlobalKey<FormState>();
  final _values = <String, Object>{};
  final _rows = <int>[1];
  late String _type = widget.document == 'PRODUCTION_NOTE'
      ? 'PRODUCTION_NOTE'
      : 'TRUCK_ARRIVAL_NOTE';
  String _note = '';

  bool get _production => _type == 'PRODUCTION_NOTE';
  int get _rowCount => _rows.fold(0, (total, rows) => total + rows);

  Widget _field(String path, String label, {bool numeric = false}) =>
      TextFormField(
        key: ValueKey(path),
        maxLength: 300,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label, counterText: ''),
        validator: (input) {
          final value = input?.trim() ?? '';
          if (!numeric || value.isEmpty) return null;
          final parsed = num.tryParse(value.replaceAll(',', '.'));
          return parsed == null || !parsed.isFinite || parsed < 0
              ? 'Isi angka yang valid.'
              : null;
        },
        onSaved: (input) {
          final value = input?.trim() ?? '';
          if (value.isNotEmpty) {
            _values[path] = numeric
                ? num.parse(value.replaceAll(',', '.'))
                : value;
          }
        },
      );

  void _save() {
    if (!_form.currentState!.validate()) return;
    _values.clear();
    _form.currentState!.save();
    if (_values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nilai yang terbaca pada foto.')),
      );
      return;
    }
    widget.onSave({
      'document_type': _type,
      'values': Map.of(_values),
      'note': _note,
      if (_production) 'rows_per_block': List.of(_rows),
    });
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Isi nota dari foto asli',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        DropdownButton<String>(
          value: _type,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'TRUCK_ARRIVAL_NOTE',
              child: Text('Nota Kedatangan Truk'),
            ),
            DropdownMenuItem(
              value: 'PRODUCTION_NOTE',
              child: Text('Nota Produksi'),
            ),
          ],
          onChanged: widget.document != 'UNKNOWN' || widget.saving
              ? null
              : (value) => setState(() => _type = value!),
        ),
        if (_production) ...[
          _field('header.production_date', 'Tanggal produksi (YYYY-MM-DD)'),
          _field('header.shift', 'Shift'),
          _field('header.chef', 'Chef'),
          for (var block = 0; block < _rows.length; block++) ...[
            const SizedBox(height: 12),
            Text('Blok tebu ${block + 1}'),
            _field('cane_blocks.$block.cane_label', 'Label tebu'),
            for (var row = 0; row < _rows[block]; row++) ..._batch(block, row),
            TextButton(
              onPressed: _rows[block] < 50 && _rowCount < 100 && !widget.saving
                  ? () => setState(() {
                      _rows[block]++;
                    })
                  : null,
              child: const Text('Tambah baris wajan'),
            ),
          ],
          TextButton(
            onPressed: _rows.length < 30 && _rowCount < 100 && !widget.saving
                ? () => setState(() {
                    _rows.add(1);
                  })
                : null,
            child: const Text('Tambah blok tebu'),
          ),
        ] else ...[
          _field('header.arrival_date', 'Tanggal kedatangan (YYYY-MM-DD)'),
          _field('header.supplier_name', 'Pemasok'),
          _field('header.vehicle_number', 'Nomor kendaraan'),
          _field('header.brix', 'Brix', numeric: true),
          _field('header.net_weight_kg', 'Berat bersih (kg)', numeric: true),
          _field('header.cane_type', 'Jenis tebu'),
          _field('header.receiving_operator', 'Operator pada nota'),
        ],
        TextFormField(
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Catatan pemeriksaan foto',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Catatan wajib diisi.'
              : null,
          onSaved: (value) => _note = value!.trim(),
        ),
        FilledButton(
          onPressed: widget.saving ? null : _save,
          child: const Text('Simpan draf manual'),
        ),
      ],
    ),
  );

  List<Widget> _batch(int block, int row) {
    final path = 'cane_blocks.$block.batches.$row';
    return [
      Text('Baris ${row + 1}'),
      _field('$path.pan_number', 'Kode wajan'),
      _field('$path.brix', 'Brix', numeric: true),
      _field('$path.cooking.isi_kg', 'Isi (kg)', numeric: true),
      _field('$path.cooking.gamping', 'Takaran gamping'),
      _field('$path.cooking.jam_turun', 'Jam turun (HH:mm)'),
      _field('$path.output.grade', 'Grade'),
      _field('$path.output.hasil_kg', 'Hasil (kg)', numeric: true),
    ];
  }
}
