import 'package:flutter/material.dart';

import 'review_api.dart';

class IntakeLotDialog extends StatefulWidget {
  const IntakeLotDialog({required this.api, required this.taskId, super.key});
  final ReviewApi api;
  final String taskId;

  @override
  State<IntakeLotDialog> createState() => _IntakeLotDialogState();
}

class _IntakeLotDialogState extends State<IntakeLotDialog> {
  final _offsets = [0];
  late Future<Json> _page = widget.api.intakeLots(widget.taskId, 0);
  Json? _selected;

  void _loadPage({int? next, bool previous = false}) {
    setState(() {
      if (previous) _offsets.removeLast();
      if (next != null) _offsets.add(next);
      _selected = null;
      _page = widget.api.intakeLots(widget.taskId, _offsets.last);
    });
  }

  String _receivedAt(Json lot) {
    final time = DateTime.parse(lot['receivedAt'] as String).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatFullDate(time)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pilih kloter penerimaan'),
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
          final lots = (page['items'] as List).cast<Json>();
          final next = page['next_offset'] as int?;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lots.isEmpty)
                  const Text(
                    'Belum ada kloter siap menerima nota di pabrik ini.',
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
                if (_offsets.length > 1 || next != null)
                  Wrap(
                    children: [
                      if (_offsets.length > 1)
                        TextButton(
                          onPressed: () => _loadPage(previous: true),
                          child: const Text('Sebelumnya'),
                        ),
                      if (next != null)
                        TextButton(
                          onPressed: () => _loadPage(next: next),
                          child: const Text('Berikutnya'),
                        ),
                    ],
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
        onPressed: _selected == null
            ? null
            : () => Navigator.pop(context, _selected),
        child: const Text('Sahkan dan catat stok'),
      ),
    ],
  );
}
