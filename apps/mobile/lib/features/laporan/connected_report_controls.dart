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
          if (reports.scope.role == 'owner')
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
          };
        }
        final job = _id == null
            ? await reports.api.requestReportExport(
                reports.scope,
                _input!,
                _key,
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
