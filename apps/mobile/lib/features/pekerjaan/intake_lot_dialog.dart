import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'review_api.dart';

class IntakeLotDialog extends StatefulWidget {
  const IntakeLotDialog({
    required this.api,
    required this.taskId,
    this.millingLabel,
    this.excludedLots = const {},
    super.key,
  });
  final ReviewApi api;
  final String taskId;
  final String? millingLabel;
  final Set<String> excludedLots;

  @override
  State<IntakeLotDialog> createState() => _IntakeLotDialogState();
}

class _IntakeLotDialogState extends State<IntakeLotDialog> {
  final _pageHeight = NiraPageHeight();
  final _offsets = [0];
  late Future<Json> _page = _fetch(0);
  Json? _selected;
  String _liters = '';
  String _occurredAt = '';

  bool get _milling => widget.millingLabel != null;
  Future<Json> _fetch(int offset) =>
      widget.api.intakeLots(widget.taskId, offset, milling: _milling);

  bool get _canSubmit =>
      _selected != null &&
      (!_milling ||
          (RegExp(r'^(0|[1-9]\d*)(\.\d+)?$').hasMatch(_liters) &&
              RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(_occurredAt) &&
              DateTime.tryParse(_occurredAt) != null));

  void _submit() {
    final selected = _selected!;
    Navigator.pop(
      context,
      _milling
          ? {
              'lot_id': selected['id'],
              'cane_label': widget.millingLabel,
              'occurred_at': _occurredAt,
              'juice_produced_liters': _liters,
            }
          : selected,
    );
  }

  void _loadPage({int? next, bool previous = false}) {
    setState(() {
      if (previous) _offsets.removeLast();
      if (next != null) _offsets.add(next);
      _selected = null;
      _page = _fetch(_offsets.last);
    });
  }

  String _receivedAt(Json lot) {
    final time = DateTime.parse(lot['receivedAt'] as String).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatFullDate(time)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _milling
          ? 'Penggilingan ${widget.millingLabel}'
          : 'Pilih kloter penerimaan',
    ),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<Json>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (!snapshot.hasData) {
            final error = snapshot.error;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is ReviewApiError
                      ? error.message
                      : 'Daftar kloter gagal dimuat.',
                ),
                TextButton(
                  onPressed: () => _loadPage(),
                  child: const Text('Muat ulang'),
                ),
              ],
            );
          }
          final page = snapshot.requireData;
          final lots = (page['items'] as List)
              .cast<Json>()
              .where((lot) => !widget.excludedLots.contains(lot['id']))
              .toList();
          final next = page['next_offset'] as int?;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NiraPageBody(
                  height: _pageHeight,
                  firstPage: _offsets.length == 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (lots.isEmpty)
                        Text(
                          _milling
                              ? 'Tidak ada kloter penggilingan pada halaman ini.'
                              : 'Belum ada kloter siap menerima nota di pabrik ini.',
                        ),
                      for (final lot in lots)
                        ListTile(
                          selected: _selected?['id'] == lot['id'],
                          leading: Icon(
                            _selected?['id'] == lot['id']
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text('${lot['displayCode'] ?? lot['id']}'),
                          subtitle: Text(
                            '${lot['supplierName']}\n${_receivedAt(lot)}',
                          ),
                          onTap: () => setState(() => _selected = lot),
                        ),
                      if (_milling && lots.isNotEmpty) ...[
                        TextFormField(
                          initialValue: _liters,
                          onChanged: (value) => setState(
                            () => _liters = value.trim().replaceAll(',', '.'),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Total nira hasil giling (L)',
                          ),
                        ),
                        TextFormField(
                          initialValue: _occurredAt,
                          onChanged: (value) =>
                              setState(() => _occurredAt = value.trim()),
                          decoration: const InputDecoration(
                            labelText: 'Waktu penggilingan dan zona waktu',
                            hintText: '2026-11-16T09:00:00+07:00',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_offsets.length > 1 || next != null)
                  NiraPagination(
                    page: _offsets.length,
                    onPrevious: _offsets.length > 1
                        ? () => _loadPage(previous: true)
                        : null,
                    onNext: next == null ? null : () => _loadPage(next: next),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _canSubmit ? _submit : null,
        child: Text(
          _milling ? 'Gunakan data penggilingan' : 'Sahkan dan catat stok',
        ),
      ),
    ],
  );
}
