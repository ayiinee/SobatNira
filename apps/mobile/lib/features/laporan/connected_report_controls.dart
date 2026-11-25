import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../kloter/kloter_date_filter.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';
import 'package:printing/printing.dart';

Future<void> filterConnectedReport(
  BuildContext context,
  ConnectedReports reports,
) async {
  final result = await showKloterDateFilter(
    context,
    reports.filter,
    today: reports.filterToday,
  );
  if (result != null) await reports.setFilter(result.selection);
}

Future<void> selectConnectedReportDimensions(
  BuildContext context,
  ConnectedReports reports,
) async {
  final selected = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _ReportDimensionsDialog(reports: reports),
  );
  if (selected != null) await reports.setDimensions(selected);
}

class _ReportDimensionsDialog extends StatefulWidget {
  const _ReportDimensionsDialog({required this.reports});
  final ConnectedReports reports;

  @override
  State<_ReportDimensionsDialog> createState() =>
      _ReportDimensionsDialogState();
}

class _ReportDimensionsDialogState extends State<_ReportDimensionsDialog> {
  late final _selected = Map<String, String>.of(widget.reports.dimensions);
  final _lots = <String, Json>{};
  bool _loading = true;
  bool _error = false;
  int? _next = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offset = _next;
    if (offset == null) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page = await widget.reports.selectionPage(offset);
      if (!mounted) return;
      setState(() {
        for (final lot in (page['items'] as List).cast<Json>()) {
          _lots[lot['lotId'] as String] = lot;
        }
        _next = page['nextOffset'] as int?;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(String key, String title, Map<String, String> options) {
    final current = _selected[key];
    return DropdownButtonFormField<String>(
      key: ValueKey((key, current)),
      initialValue: current ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        const DropdownMenuItem(value: '', child: Text('Semua')),
        if (current != null && !options.containsKey(current))
          DropdownMenuItem(value: current, child: const Text('Filter aktif')),
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) => setState(() {
        _selected.remove(key);
        if (value != null && value.isNotEmpty) _selected[key] = value;
        if (key == 'supplierId') _selected.remove('lotId');
        if (key == 'supplierId' || key == 'lotId') _selected.remove('batchId');
        if (key != 'grade') _selected.remove('grade');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bySupplier = _lots.values.where(
      (lot) =>
          _selected['supplierId'] == null ||
          lot['supplierId'] == _selected['supplierId'],
    );
    final batches = bySupplier
        .where(
          (lot) =>
              _selected['lotId'] == null || lot['lotId'] == _selected['lotId'],
        )
        .expand((lot) => (lot['batches'] as List).cast<Json>());
    return AlertDialog(
      title: const Text('Filter data laporan'),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('supplierId', 'Pemasok', {
                for (final lot in _lots.values)
                  if (lot['supplierId'] case final String id)
                    id: lot['supplier'] as String,
              }),
              _field('lotId', 'Kloter', {
                for (final lot in bySupplier)
                  lot['lotId'] as String: lot['code'] as String,
              }),
              _field('batchId', 'Batch', {
                for (final batch in batches)
                  batch['id'] as String: batch['code'] as String,
              }),
              _field('grade', 'Grade', {
                for (final batch in batches)
                  if (_selected['batchId'] == null ||
                      batch['id'] == _selected['batchId'])
                    for (final grade in (batch['grades'] as List).cast<Json>())
                      grade['code'] as String: grade['code'] as String,
              }),
              if (_loading)
                const NiraLoading(label: 'Memuat pilihan…', compact: true),
              if (!_loading && _next != null)
                TextButton(
                  onPressed: _load,
                  child: Text(
                    _error
                        ? 'Coba lagi memuat pilihan'
                        : 'Muat pilihan berikutnya',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, <String, String>{}),
          child: const Text('Hapus filter'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}

class ConnectedReportStatus extends StatelessWidget {
  const ConnectedReportStatus({
    required this.reports,
    this.compact = false,
    super.key,
  });
  final ConnectedReports reports;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (reports.loading) {
      return NiraLoading(label: 'Memuat laporan…', compact: compact);
    }
    if (reports.error != null) {
      return Column(
        children: [
          Text(
            reports.error is ReviewApiError
                ? (reports.error as ReviewApiError).message
                : 'Laporan gagal dimuat.',
          ),
          TextButton(
            onPressed: reports.refresh,
            child: const Text('Coba lagi memuat laporan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PagedReportDetails(reports: reports),
              ),
            ),
            child: const Text('Lihat rincian per halaman'),
          ),
          if (const {'admin', 'owner'}.contains(reports.scope.role))
            AsyncReportExport(reports: reports),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class PagedReportDetails extends StatefulWidget {
  const PagedReportDetails({required this.reports, super.key});
  final ConnectedReports reports;
  @override
  State<PagedReportDetails> createState() => _PagedReportDetailsState();
}

class _PagedReportDetailsState extends State<PagedReportDetails> {
  int _offset = 0;
  late final _synthetic = widget.reports.synthetic;
  late final _range = widget.reports.filter?.range;
  late Future<Json> _request = _load();
  Future<Json> _load() {
    final request = widget.reports.api.reportDetailPage(
      widget.reports.scope,
      synthetic: _synthetic,
      offset: _offset,
      selection: widget.reports.dimensions,
      from: _range?.start,
      before: _range == null
          ? null
          : DateTime(_range.end.year, _range.end.month, _range.end.day + 1),
    );
    // Errors may arrive before FutureBuilder subscribes on the next frame.
    request.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return request;
  }

  void _page(int offset) => setState(() {
    _offset = offset;
    _request = _load();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rincian laporan')),
    body: FutureBuilder<Json>(
      future: _request,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NiraLoading(label: 'Memuat rincian laporan…');
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error is ReviewApiError
                      ? (snapshot.error as ReviewApiError).message
                      : 'Rincian belum dapat dimuat.',
                ),
                TextButton(
                  onPressed: () => _page(_offset),
                  child: const Text('Coba lagi halaman laporan'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const NiraLoading(label: 'Memuat rincian laporan…');
        }
        final data = snapshot.requireData,
            totals = snapshot.requireData['totals'] as Json;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Total seluruh periode: ${totals['lotCount']} kloter'),
            Text(
              'Margin seluruh periode: ${reportMoney(totals['productionMarginRupiah'])}',
            ),
            const Text(
              'Baris di bawah hanya halaman ini. Total berasal dari seluruh filter; gunakan ekspor server untuk dokumen lengkap.',
            ),
            for (final row in (data['items'] as List).cast<Json>())
              ExpansionTile(
                title: Text(row['code'] as String),
                subtitle: Text(row['supplier'] as String),
                children: [
                  Text('Tebu: ${row['caneNetKg']} kg'),
                  Text(
                    'Margin: ${row['calculation'] == null ? 'Belum tersedia' : reportMoney((row['calculation'] as Json)['productionMarginRupiah'])}',
                  ),
                  for (final batch in (row['batches'] as List).cast<Json>())
                    ListTile(
                      title: Text(batch['code'] as String),
                      subtitle: Text('Gula final: ${batch['finalSugarKg']} kg'),
                    ),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _offset > 0
                      ? () => _page((_offset - 20).clamp(0, _offset))
                      : null,
                  child: const Text('Sebelumnya'),
                ),
                TextButton(
                  onPressed: data['nextOffset'] == null
                      ? null
                      : () => _page(data['nextOffset'] as int),
                  child: const Text('Berikutnya'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class AsyncReportExport extends StatefulWidget {
  const AsyncReportExport({required this.reports, super.key});
  final ConnectedReports reports;
  @override
  State<AsyncReportExport> createState() => _AsyncReportExportState();
}

class _AsyncReportExportState extends State<AsyncReportExport> {
  String? _id;
  String? _status;
  String? _error;
  bool _busy = false;
  String _key = ReviewApi.requestUuid();
  Json? _input;
  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reports = widget.reports;
    try {
      if (_status == 'READY') {
        final bytes = await reports.api.reportExportPdf(reports.scope, _id!);
        await Printing.sharePdf(bytes: bytes, filename: 'sobatnira-$_id.pdf');
      } else {
        if (_input == null) {
          final chosen = await showKloterDateFilter(
            context,
            reports.filter,
            today: reports.filterToday,
          );
          if (chosen?.selection == null) return;
          final range = chosen!.selection!.range;
          _input = {
            'from': range.start.toUtc().toIso8601String(),
            'before': DateTime(
              range.end.year,
              range.end.month,
              range.end.day + 1,
            ).toUtc().toIso8601String(),
            'synthetic': reports.synthetic,
            'selection': reports.dimensions,
          };
        }
        final job = _id == null
            ? await reports.api.requestReportExport(
                reports.scope,
                from: DateTime.parse(_input!['from'] as String),
                before: DateTime.parse(_input!['before'] as String),
                synthetic: _input!['synthetic'] as bool,
                requestId: _key,
                selection:
                    _input!['selection'] as Map<String, String>? ?? const {},
              )
            : await reports.api.reportExportStatus(reports.scope, _id!);
        _id = job['id'] as String;
        _status = job['status'] as String;
      }
    } catch (error) {
      _error = error is ReviewApiError
          ? error.message
          : 'Ekspor belum dapat diproses.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_id != null) Text('Ekspor $_id: $_status'),
      if (_error != null) Text(_error!),
      if ((_error != null || _status == 'FAILED') && !_busy)
        TextButton(
          onPressed: () => setState(() {
            _key = ReviewApi.requestUuid();
            _id = null;
            _input = null;
            _status = null;
            _error = null;
          }),
          child: const Text('Pilih periode ekspor baru'),
        ),
      if (_status == 'FAILED')
        const Text('Ekspor gagal. Persempit periode dan buat permintaan baru.')
      else
        TextButton(
          onPressed: _busy ? null : _run,
          child: Text(
            _busy
                ? 'Memproses ekspor…'
                : _status == 'READY'
                ? 'Unduh PDF'
                : _id == null
                ? 'Ekspor laporan di server'
                : 'Periksa status ekspor',
          ),
        ),
    ],
  );
}
