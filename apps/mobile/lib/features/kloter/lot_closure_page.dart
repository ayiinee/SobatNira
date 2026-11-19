import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import '../pekerjaan/review_api.dart';
import '../pekerjaan/production_api.dart';

class LotClosurePage extends StatefulWidget {
  const LotClosurePage({
    super.key,
    required this.api,
    required this.scope,
    this.onNavigate,
    required this.lotId,
  });
  final ValueChanged<NiraTab>? onNavigate;
  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;

  @override
  State<LotClosurePage> createState() => _LotClosurePageState();
}

class _LotClosurePageState extends State<LotClosurePage> {
  final _pageHeight = NiraPageHeight();
  int _offset = 0;
  bool _working = false;
  bool _submitting = false;
  String? _notice;
  late Future<List<Json>> _data = _load();

  Future<List<Json>> _load() {
    final request = Future.wait([
      widget.api.lotClosure(widget.scope, widget.lotId),
      widget.api.lotClosureHistory(widget.scope, widget.lotId, offset: _offset),
    ]);
    // A refresh can fail before FutureBuilder subscribes on the next frame.
    request.ignore();
    return request;
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _change(Json status) async {
    if (_working) return;
    final reopen = status['status'] == 'closed';
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      String? reason;
      if (reopen) {
        reason = await showDialog<String>(
          context: context,
          builder: (_) => const _ReopenDialog(),
        );
        if (reason == null) return;
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tutup kloter?'),
            content: const Text(
              'Pengesahan penggilingan, saldo nira, reservasi, dan kesiapan batch akan diperiksa sebelum kloter ditutup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Tutup kloter'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      if (!mounted) return;
      setState(() => _submitting = true);
      final closure = ClosureApi(widget.api);
      if (reopen) {
        await closure.reopen(
          widget.scope,
          widget.lotId,
          status['closureId'] as String,
          reason!,
        );
      } else {
        await closure.close(widget.scope, widget.lotId);
      }
      if (mounted) {
        setState(() {
          _notice = reopen
              ? 'Permintaan buka kembali tercatat.'
              : 'Permintaan penutupan tercatat.';
          _offset = 0;
          _data = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = switch (error) {
            ReviewApiError(status: 409) =>
              reopen
                  ? 'Penutupan atau alasan sudah berubah. Periksa status terbaru sebelum membuka kembali.'
                  : 'Kloter belum dapat ditutup. Periksa pengesahan penggilingan, saldo nira, reservasi, dan kesiapan batch.',
            ReviewApiError(status: 503) =>
              'Pemeriksaan penutupan belum tersedia. Muat ulang setelah layanan kembali tersedia.',
            ReviewApiError() => error.message,
            _ =>
              'Hasil permintaan belum terkonfirmasi. Periksa status dan riwayat terbaru sebelum mencoba lagi.',
          };
          _offset = 0;
          _data = _load();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _submitting = false;
        });
      }
    }
  }

  String _time(Object value) {
    final time = DateTime.parse(value as String).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatFullDate(time)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }

  Widget _person(String label, Object value) =>
      ListTile(title: Text(label), subtitle: SelectableText('$value'));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: NiraPageScaffold(
      onNavigate: widget.onNavigate == null
          ? null
          : (tab) {
              if (!_working) widget.onNavigate!(tab);
            },
      title: const Text('Penutupan dan riwayat'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang penutupan',
          onPressed: _working ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.scope.factoryName),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_notice!),
              ),
            if (_submitting) const LinearProgressIndicator(),
            NiraPagedFutureBuilder<List<Json>>(
              future: _data,
              page: _offset,
              dataset: (widget.scope.factoryId, widget.lotId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Column(
                    children: [
                      Text(
                        error is ReviewApiError
                            ? error.message
                            : 'Status dan riwayat gagal dimuat.',
                      ),
                      if (error is ReviewApiError && error.status == 401)
                        const Text(
                          'Kembali ke daftar kloter dan masuk ulang melalui menu Keluar.',
                        ),
                      TextButton(
                        onPressed: _working ? null : _reload,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  );
                }
                final [status, page] = snapshot.requireData;
                final closed = status['status'] == 'closed';
                final rows = (page['items'] as List).cast<Json>();
                final limit = page['limit'] as int;
                final total = page['total'] as int;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: const Text('Status kloter'),
                      subtitle: Text(closed ? 'Ditutup' : 'Terbuka'),
                    ),
                    if (closed) ...[
                      ListTile(
                        title: const Text('Waktu penutupan'),
                        subtitle: Text(_time(status['closedAt'] as String)),
                      ),
                      _person('Ditutup oleh', status['closedBy'] as String),
                    ],
                    FilledButton(
                      onPressed: _working ? null : () => _change(status),
                      child: Text(
                        closed ? 'Buka kembali kloter' : 'Tutup kloter',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Riwayat penutupan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Waktu ditampilkan sesuai zona waktu perangkat.',
                    ),
                    NiraPageBody(
                      height: _pageHeight,
                      firstPage: _offset == 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (rows.isEmpty)
                            const ListTile(
                              title: Text(
                                'Belum ada riwayat pada halaman ini.',
                              ),
                            ),
                          for (final entry in rows)
                            ExpansionTile(
                              key: ValueKey(entry['id']),
                              title: Text(
                                'Ditutup · ${_time(entry['closedAt'] as String)}',
                              ),
                              subtitle: Text(
                                entry['reopenedAt'] == null
                                    ? 'Penutupan aktif'
                                    : 'Sudah dibuka kembali',
                              ),
                              children: [
                                _person('ID penutupan', entry['id'] as String),
                                _person(
                                  'Ditutup oleh',
                                  entry['closedBy'] as String,
                                ),
                                if (entry['reopenedAt'] != null) ...[
                                  ListTile(
                                    title: const Text('Dibuka kembali pada'),
                                    subtitle: Text(
                                      _time(entry['reopenedAt'] as String),
                                    ),
                                  ),
                                  _person(
                                    'Dibuka kembali oleh',
                                    entry['reopenedBy'] as String,
                                  ),
                                  ListTile(
                                    title: const Text('Alasan buka kembali'),
                                    subtitle: Text(entry['reason'] as String),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (_offset > 0 || total > limit)
                      NiraPagination(
                        page: _offset ~/ limit + 1,
                        pageCount: (total / limit).ceil(),
                        onPrevious: !_working && _offset > 0
                            ? () {
                                _offset -= limit;
                                _reload();
                              }
                            : null,
                        onNext: !_working && _offset + limit < total
                            ? () {
                                _offset += limit;
                                _reload();
                              }
                            : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReopenDialog extends StatefulWidget {
  const _ReopenDialog();
  @override
  State<_ReopenDialog> createState() => _ReopenDialogState();
}

class _ReopenDialogState extends State<_ReopenDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Buka kembali kloter'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _reason,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Alasan buka kembali'),
        validator: (value) =>
            value!.trim().isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
            ? 'Isi alasan tanpa baris baru atau karakter kontrol.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Buka kembali'),
      ),
    ],
  );
}
