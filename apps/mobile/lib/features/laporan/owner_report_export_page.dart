import 'dart:async';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import '../kloter/demo_production.dart' show formatDate;
import '../kloter/kloter_date_filter.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';
import 'save_report_file.dart';

class OwnerReportExportPage extends StatefulWidget {
  const OwnerReportExportPage({required this.reports, super.key});

  final ConnectedReports reports;

  @override
  State<OwnerReportExportPage> createState() => _OwnerReportExportPageState();
}

class _OwnerReportExportPageState extends State<OwnerReportExportPage> {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
    caseSensitive: false,
  );
  final _lookupId = TextEditingController();
  late KloterDateFilter? _filter = widget.reports.filter;
  late final bool _synthetic = widget.reports.synthetic;
  Json? _job;
  String? _requestId;
  String? _error;
  String? _message;
  bool _busy = false;
  bool _polling = false;
  Timer? _poll;
  DateTime? _pollUntil;

  ReviewApi get _api => widget.reports.api;
  FactoryScope get _scope => widget.reports.scope;
  bool get _inProgress =>
      _job?['status'] == 'QUEUED' || _job?['status'] == 'PROCESSING';

  @override
  void dispose() {
    _poll?.cancel();
    _lookupId.dispose();
    super.dispose();
  }

  Future<void> _choosePeriod() async {
    final result = await showKloterDateFilter(
      context,
      _filter,
      today: widget.reports.filterToday,
    );
    if (!mounted || result == null) return;
    setState(() {
      _filter = result.selection;
      _error = null;
    });
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    if (_busy || _polling) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = _errorText(error, fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(Object error, String fallback) => switch (error) {
    ReviewApiError(status: 503) =>
      'Ekspor laporan belum tersedia. Coba lagi nanti.',
    ReviewApiError(status: 409) =>
      'Ekspor belum dapat diproses. Cek statusnya kembali.',
    ReviewApiError(status: 400) => 'Periksa periode atau ID ekspor.',
    ReviewApiError(status: 401 || 403 || 404) => error.message,
    _ => fallback,
  };

  Future<void> _request() async {
    final range = _filter?.range;
    if (range == null) return;
    final last = range.end;
    final before = DateTime(last.year, last.month, last.day + 1);
    if (before.difference(range.start) > const Duration(days: 366)) {
      setState(() => _error = 'Pilih periode paling lama 366 hari.');
      return;
    }
    await _run(
      () async {
        _poll?.cancel();
        _job = null;
        _requestId ??= ReviewApi.requestUuid();
        try {
          final job = await _api.requestReportExport(
            _scope,
            from: range.start,
            before: before,
            synthetic: _synthetic,
            requestId: _requestId!,
            selection: widget.reports.dimensions,
          );
          if (!mounted) return;
          _display(job);
          _requestId = null;
        } on ReviewApiError catch (error) {
          if (error.status >= 400 &&
              error.status < 500 &&
              error.status != 408 &&
              error.status != 429) {
            _requestId = null;
          }
          rethrow;
        }
      },
      'Permintaan ekspor belum terkonfirmasi. Ketuk Coba lagi untuk melanjutkan.',
    );
  }

  Future<void> _lookup(String id) async {
    if (!_uuid.hasMatch(id)) {
      setState(() => _error = 'Masukkan ID ekspor yang valid.');
      return;
    }
    await _run(() async {
      if (_job?['id'] != id) {
        _job = null;
        _poll?.cancel();
      }
      final job = await _api.reportExportStatus(_scope, id);
      if (mounted) _display(job, expectedId: id);
    }, 'Status ekspor gagal dimuat. Coba lagi.');
  }

  void _display(Json job, {String? expectedId, bool restartPolling = true}) {
    final id = job['id'];
    final status = job['status'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        (expectedId != null && id.toLowerCase() != expectedId.toLowerCase()) ||
        !const {'QUEUED', 'PROCESSING', 'READY', 'FAILED'}.contains(status)) {
      throw const FormatException('Status ekspor tidak lengkap.');
    }
    _job = job;
    if (restartPolling) {
      _lookupId.text = id;
      _pollUntil = DateTime.now().add(const Duration(minutes: 1));
    }
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_inProgress || !DateTime.now().isBefore(_pollUntil!)) return;
    _poll = Timer(const Duration(seconds: 3), () async {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (_busy) {
        _schedulePoll();
        return;
      }
      final id = _job!['id'] as String;
      _polling = true;
      try {
        final job = await _api.reportExportStatus(_scope, id);
        if (mounted) _display(job, expectedId: id, restartPolling: false);
      } catch (error) {
        if (mounted) {
          _error = _errorText(error, 'Cek status untuk melanjutkan.');
        }
      } finally {
        if (mounted) setState(() => _polling = false);
      }
    });
  }

  Future<void> _download(ReportFileFormat format) async {
    final id = _job!['id'] as String;
    await _run(() async {
      final bytes = await _api.reportExportFile(_scope, id, format);
      if (!mounted) return;
      final saved = await saveReportFile(
        bytes,
        'sobatnira-laporan-$id.${format.name}',
        format.mimeType,
      );
      if (mounted && saved) {
        _message = 'File ${format.name.toUpperCase()} disimpan.';
      }
    }, 'File gagal disimpan. Coba lagi.');
  }

  @override
  Widget build(BuildContext context) {
    final range = _filter?.range;
    final busy = _busy || _polling;
    final status = _job?['status'];
    final formats = _job?['formats'];
    final secondaryAction = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(
        horizontal: NiraSpace.md,
        vertical: NiraSpace.sm,
      ),
      side: const BorderSide(color: niraLine),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(niraRadius),
      ),
    );
    return NiraPageScaffold(
      title: const Text('Ekspor laporan'),
      body: ListView(
        padding: EdgeInsets.all(niraPageInset(context)),
        children: [
          _section(
            icon: Icons.description_outlined,
            title: 'Buat ekspor',
            children: [
              OutlinedButton(
                style: secondaryAction,
                onPressed: busy || _requestId != null ? null : _choosePeriod,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: NiraSpace.sm),
                    Expanded(
                      child: Text(
                        range == null
                            ? 'Pilih periode ekspor'
                            : '${formatDate(range.start)} – ${formatDate(range.end)}',
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
              if (_synthetic)
                Text(
                  'Menggunakan data sintetis.',
                  style: niraText(NiraType.caption, color: niraLeaf),
                ),
              FilledButton(
                onPressed: busy || range == null ? null : _request,
                child: Text(_requestId == null ? 'Buat laporan' : 'Coba lagi'),
              ),
            ],
          ),
          const SizedBox(height: NiraSpace.lg),
          _section(
            icon: Icons.chat_bubble_outline,
            title: 'Buka ekspor dari WhatsApp',
            spacing: NiraSpace.lg,
            children: [
              TextField(
                controller: _lookupId,
                enabled: !busy,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'ID ekspor',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Tempel ID dari WhatsApp',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(niraRadius)),
                    borderSide: BorderSide(color: niraLine),
                  ),
                ),
                onSubmitted: (value) => _lookup(value.trim()),
              ),
              OutlinedButton.icon(
                style: secondaryAction,
                onPressed: busy ? null : () => _lookup(_lookupId.text.trim()),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Cek status'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: NiraSpace.lg),
            const LinearProgressIndicator(semanticsLabel: 'Memuat ekspor'),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: NiraSpace.lg),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: niraText(
                  NiraType.body,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          if (_job case final job?) ...[
            const SizedBox(height: NiraSpace.lg),
            _section(
              icon: status == 'READY'
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              announceTitle: true,
              title: switch (status) {
                'QUEUED' => 'Dalam antrean',
                'PROCESSING' => 'Sedang diproses',
                'READY' => 'File siap diunduh',
                _ => 'Ekspor gagal. Buat laporan baru untuk mencoba lagi.',
              },
              children: [
                SelectableText('ID ekspor ${job['id']}'),
                if (job['synthetic'] == true)
                  const Text('Laporan data sintetis'),
                if (status == 'READY' && formats is List)
                  for (final format in ReportFileFormat.values)
                    if (formats.contains(format.name))
                      OutlinedButton.icon(
                        style: secondaryAction,
                        onPressed: busy ? null : () => _download(format),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text('Unduh ${format.name.toUpperCase()}'),
                      ),
                if (_message case final message?)
                  Semantics(liveRegion: true, child: Text(message)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool announceTitle = false,
    double spacing = NiraSpace.md,
  }) => Container(
    padding: const EdgeInsets.all(NiraSpace.lg),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: niraLine),
      borderRadius: BorderRadius.circular(niraRadius * 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(NiraSpace.sm),
              decoration: BoxDecoration(
                color: niraGreen.withValues(alpha: .075),
                borderRadius: BorderRadius.circular(niraRadius),
              ),
              child: Icon(icon, size: 20, color: niraGreen),
            ),
            const SizedBox(width: NiraSpace.md),
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: announceTitle,
                child: Text(
                  title,
                  style: niraText(NiraType.section, weight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        ...children,
      ],
    ),
  );
}
