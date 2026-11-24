import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_date_filter.dart';

import 'review_api.dart';
import 'review_detail_page.dart';

class PekerjaanPage extends StatefulWidget {
  const PekerjaanPage({
    this.api,
    this.factoryId,
    this.onNavigate,
    required this.active,
    super.key,
  });
  final ValueChanged<NiraTab>? onNavigate;
  final ReviewApi? api;
  final String? factoryId;
  final bool active;

  @override
  State<PekerjaanPage> createState() => _PekerjaanPageState();
}

class _PekerjaanPageState extends State<PekerjaanPage>
    with WidgetsBindingObserver {
  final _pageHeight = NiraPageHeight();
  final _email = TextEditingController();
  final _password = TextEditingController();
  ReviewApi? _session;
  Future<List<Json>>? _tasks;
  String _status = 'PENDING_VALIDATION';
  String? _documentType;
  KloterDateFilter? _received;
  int _page = 1;
  bool _signingIn = false;
  String? _error;
  Timer? _notifications;
  int _unread = 0;

  ReviewApi? get _api => widget.api ?? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleNotifications();
  }

  @override
  void didUpdateWidget(PekerjaanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _scheduleNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _scheduleNotifications();
  }

  void _scheduleNotifications() {
    _notifications?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (!widget.active ||
        _api == null ||
        (state != null && state != AppLifecycleState.resumed)) {
      return;
    }
    unawaited(_loadNotifications());
    _notifications = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadNotifications(),
    );
  }

  Future<void> _loadNotifications() async {
    final api = _api;
    if (api == null) return;
    try {
      final count = await api.unreadNotifications(factoryId: widget.factoryId);
      if (mounted && identical(_api, api) && _unread != count) {
        setState(() => _unread = count);
      }
    } catch (_) {
      // The review queue is independent of the notification request.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications?.cancel();
    _email.dispose();
    _password.dispose();
    _session?.close();
    super.dispose();
  }

  void _load() {
    final range = _received?.range;
    final end = range?.end;
    _tasks = _api?.list(
      _status,
      _page,
      factoryId: widget.factoryId,
      documentType: _documentType,
      receivedFrom: range?.start,
      receivedBefore: end == null
          ? null
          : DateTime(end.year, end.month, end.day + 1),
    );
  }

  Future<void> _pickReceived() async {
    final result = await showKloterDateFilter(
      context,
      _received,
      today: DateTime.now(),
    );
    if (!mounted || result == null) return;
    setState(() {
      _received = result.selection;
      _page = 1;
      _load();
    });
  }

  String? _receivedLabel(Object? value) {
    final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    if (date == null) return null;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return 'Diterima ${formatDate(date)} · $hour:$minute';
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final session = await ReviewApi.signIn(
        _email.text.trim(),
        _password.text,
      );
      if (!mounted) {
        session.close();
        return;
      }
      _password.clear();
      setState(() {
        _session = session;
        _load();
      });
      _scheduleNotifications();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal masuk. Periksa akun dan koneksi.');
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _signOut() {
    _notifications?.cancel();
    _session?.close();
    setState(() {
      _session = null;
      _tasks = null;
      _page = 1;
      _unread = 0;
    });
  }

  Future<void> _open(Json task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReviewDetailPage(
          api: _api!,
          taskId: task['id'] as String,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
    if (mounted) {
      setState(_load);
      unawaited(_loadNotifications());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      niraPageInset(context),
      NiraSpace.lg,
      niraPageInset(context),
      NiraSpace.lg,
    ),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Pekerjaan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (_session != null)
            TextButton(onPressed: _signOut, child: const Text('Keluar')),
        ],
      ),
      const SizedBox(height: 16),
      if (_api == null)
        ..._login()
      else ...[
        if (_unread > 0)
          Card(
            margin: const EdgeInsets.only(bottom: NiraSpace.md),
            color: niraGreen.withValues(alpha: .075),
            elevation: 0,
            child: ListTile(
              leading: const Icon(
                Icons.notifications_outlined,
                color: niraGreen,
              ),
              trailing: const Icon(Icons.chevron_right, color: niraLeaf),
              title: Text('$_unread laporan baru'),
              onTap: () => setState(() {
                _status = 'PENDING_VALIDATION';
                _documentType = null;
                _received = null;
                _page = 1;
                _load();
              }),
            ),
          ),
        _filters(),
        const SizedBox(height: NiraSpace.xl),
        NiraPagedFutureBuilder<List<Json>>(
          future: _tasks,
          page: _page,
          dataset: (_api, widget.factoryId, _status, _documentType, _received),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const NiraLoading(label: 'Memuat pekerjaan…');
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return _queueMessage(
                icon: Icons.error_outline,
                message: error is ReviewApiError
                    ? error.message
                    : 'Gagal memuat antrean.',
                action: TextButton(
                  onPressed:
                      error is ReviewApiError &&
                          error.status == 401 &&
                          _session != null
                      ? _signOut
                      : () => setState(_load),
                  child: const Text('Coba lagi'),
                ),
              );
            }
            final tasks = snapshot.data ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NiraPageBody(
                  height: _pageHeight,
                  firstPage: _page == 1,
                  child: tasks.isEmpty
                      ? _queueMessage(
                          icon: Icons.inbox_outlined,
                          message: _documentType == null && _received == null
                              ? 'Belum ada laporan pada status ini.'
                              : 'Belum ada laporan yang sesuai filter.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: NiraSpace.sm,
                          children: [for (final task in tasks) _taskCard(task)],
                        ),
                ),
                if (_page > 1 || tasks.length == 20) ...[
                  const SizedBox(height: NiraSpace.md),
                  NiraPagination(
                    page: _page,
                    onPrevious: _page > 1
                        ? () => setState(() {
                            _page--;
                            _load();
                          })
                        : null,
                    onNext: tasks.length == 20
                        ? () => setState(() {
                            _page++;
                            _load();
                          })
                        : null,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ],
  );

  Widget _filters() => Container(
    padding: const EdgeInsets.all(NiraSpace.md),
    decoration: BoxDecoration(
      color: niraGreen.withValues(alpha: .045),
      border: Border.all(color: niraLine),
      borderRadius: BorderRadius.circular(niraRadius * 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NiraSpace.md,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_status),
          initialValue: _status,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status nota'),
          items: const [
            DropdownMenuItem(
              value: 'PENDING_VALIDATION',
              child: Text('Menunggu validasi'),
            ),
            DropdownMenuItem(value: 'VALIDATED', child: Text('Tervalidasi')),
            DropdownMenuItem(
              value: 'RETURNED_FOR_CORRECTION',
              child: Text('Dikembalikan'),
            ),
            DropdownMenuItem(
              value: 'MANUAL_REVIEW_REQUIRED',
              child: Text('Perlu tinjauan manual'),
            ),
          ],
          onChanged: (value) => setState(() {
            _status = value!;
            _page = 1;
            _load();
          }),
        ),
        DropdownButtonFormField<String>(
          initialValue: _documentType,
          key: ValueKey(_documentType),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Jenis nota'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Semua jenis nota')),
            DropdownMenuItem(
              value: 'TRUCK_ARRIVAL_NOTE',
              child: Text('Nota Kedatangan Truk'),
            ),
            DropdownMenuItem(
              value: 'PRODUCTION_NOTE',
              child: Text('Nota Produksi'),
            ),
            DropdownMenuItem(value: 'UNKNOWN', child: Text('Belum dikenali')),
          ],
          onChanged: (value) => setState(() {
            _documentType = value;
            _page = 1;
            _load();
          }),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: NiraSpace.md),
            backgroundColor: Colors.white,
            side: const BorderSide(color: niraLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(niraRadius),
            ),
          ),
          onPressed: _pickReceived,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(switch (_received?.range) {
            final range? =>
              '${formatDate(range.start)} – ${formatDate(range.end)}',
            null => 'Filter tanggal penerimaan',
          }, textAlign: TextAlign.center),
        ),
      ],
    ),
  );

  Widget _taskCard(Json task) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: niraLine),
      borderRadius: BorderRadius.circular(niraRadius * 1.5),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: NiraSpace.md),
      minVerticalPadding: NiraSpace.md,
      horizontalTitleGap: NiraSpace.md,
      leading: Container(
        padding: const EdgeInsets.all(NiraSpace.sm),
        decoration: BoxDecoration(
          color: niraGreen.withValues(alpha: .075),
          borderRadius: BorderRadius.circular(niraRadius),
        ),
        child: Icon(
          task['document_type'] == 'TRUCK_ARRIVAL_NOTE'
              ? Icons.local_shipping_outlined
              : Icons.description_outlined,
          color: niraGreen,
          size: 20,
        ),
      ),
      title: Text(
        documentType(task['document_type']),
        style: niraText(NiraType.body, weight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: NiraSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: NiraSpace.xs,
          children: [
            Text(
              '${task['sender_name']} · Revisi ${task['version']} · ${task['issue_count']} temuan',
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
            if (_receivedLabel(task['received_at']) case final received?)
              Text(
                received,
                style: niraText(NiraType.caption, color: niraLeaf),
              ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: niraLeaf, size: 20),
      onTap: () => _open(task),
    ),
  );

  Widget _queueMessage({
    required IconData icon,
    required String message,
    Widget? action,
  }) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: NiraSpace.xl),
      child: Column(
        spacing: NiraSpace.sm,
        children: [
          Icon(icon, color: niraLeaf),
          Text(message, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );

  List<Widget> _login() {
    if (supabaseProject.isEmpty || supabasePublicKey.isEmpty) {
      return [
        const Text('Akses Pekerjaan belum dikonfigurasi untuk build ini.'),
      ];
    }
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: NiraSpace.md),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Kata sandi'),
        onSubmitted: (_) {
          if (!_signingIn) _signIn();
        },
      ),
      if (_error != null) Text(_error!),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _signingIn ? null : _signIn,
        child: Text(_signingIn ? 'Memproses…' : 'Masuk'),
      ),
    ];
  }
}
