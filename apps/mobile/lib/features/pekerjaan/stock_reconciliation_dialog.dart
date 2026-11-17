import 'package:flutter/material.dart';

import 'review_api.dart';

class StockReconciliationDialog extends StatefulWidget {
  const StockReconciliationDialog({
    required this.intake,
    required this.milling,
    super.key,
  });
  final Json? intake;
  final List<Json> milling;

  @override
  State<StockReconciliationDialog> createState() =>
      _StockReconciliationDialogState();
}

class _StockReconciliationDialogState extends State<StockReconciliationDialog> {
  late Json _target = widget.intake ?? widget.milling.first;
  String _quantity = '';
  String _reason = '';

  @override
  Widget build(BuildContext context) {
    final isCane = widget.intake != null;
    final unit = isCane ? 'kg' : 'L';
    final current = _target[isCane ? 'net_weight_kg' : 'juice_produced_liters'];
    final valid =
        RegExp(r'^(0|[1-9]\d*)(\.\d+)?$').hasMatch(_quantity) &&
        _reason.isNotEmpty;
    return AlertDialog(
      title: const Text('Koreksi stok nota sah'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.milling.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _target['lot_id'] as String,
              decoration: const InputDecoration(labelText: 'Blok tebu'),
              items: [
                for (final item in widget.milling)
                  DropdownMenuItem(
                    value: item['lot_id'] as String,
                    child: Text('${item['cane_label']}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(
                  () => _target = widget.milling.firstWhere(
                    (item) => item['lot_id'] == value,
                  ),
                );
              },
            ),
          Text('Kuantitas saat ini ${current ?? '—'} $unit'),
          TextFormField(
            decoration: InputDecoration(
              labelText: 'Kuantitas yang benar ($unit)',
            ),
            maxLength: 64,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) =>
                setState(() => _quantity = value.trim().replaceAll(',', '.')),
          ),
          TextFormField(
            decoration: const InputDecoration(labelText: 'Alasan koreksi'),
            maxLength: 500,
            maxLines: 2,
            onChanged: (value) => setState(() => _reason = value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, {
                  'lot_id': _target['lot_id'],
                  'quantity': _quantity,
                  'reason': _reason,
                })
              : null,
          child: const Text('Sahkan koreksi stok'),
        ),
      ],
    );
  }
}
