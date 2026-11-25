import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';
import '../laporan/connected_reports.dart';
import '../pekerjaan/review_api.dart';
import 'settings_widgets.dart';

class CostCorrectionInbox extends StatefulWidget {
  const CostCorrectionInbox({
    required this.api,
    required this.scope,
    super.key,
  });

  final ReviewApi api;
  final FactoryScope scope;

  @override
  State<CostCorrectionInbox> createState() => _CostCorrectionInboxState();
}

class _CostCorrectionInboxState extends State<CostCorrectionInbox> {
  int _offset = 0;
  late Future<Json> _page = widget.api.lotCostCorrections(widget.scope);
  bool _busy = false;
  bool _changed = false;

  void _load(int offset) => setState(() {
    _offset = offset;
    _page = widget.api.lotCostCorrections(widget.scope, offset: offset);
  });

  Future<void> _approve(Json item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Setujui koreksi biaya?'),
        content: Text('Setujui biaya baru untuk ${item['lotCode']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.approveLotCostCorrection(
        widget.scope,
        item['lotId'] as String,
        item['id'] as String,
      );
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koreksi biaya disetujui.')),
        );
        _load(0);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ReviewApiError
                  ? error.detail ?? error.message
                  : 'Persetujuan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.',
            ),
          ),
        );
        _load(0);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_busy && !_changed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy && _changed) Navigator.pop(context, true);
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Pengajuan koreksi biaya')),
      body: FutureBuilder<Json>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: NiraLoading(label: 'Memuat pengajuan…'));
          }
          if (snapshot.hasError) {
            return Center(
              child: SettingsLoadError(
                accessDenied:
                    snapshot.error is ReviewApiError &&
                    (snapshot.error as ReviewApiError).status == 403,
                message: 'Pengajuan koreksi belum bisa dimuat.',
                onRetry: () => _load(_offset),
              ),
            );
          }
          final page = snapshot.requireData;
          final items = (page['items'] as List).cast<Json>();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty)
                const Text('Belum ada pengajuan koreksi biaya.'),
              for (final item in items)
                ExpansionTile(
                  title: Text(item['lotCode'] as String),
                  subtitle: Text(switch (item['status']) {
                    'pending' => 'Menunggu persetujuan',
                    'approved' => 'Disetujui',
                    _ => 'Perlu diajukan ulang',
                  }),
                  children: [
                    ListTile(
                      title: const Text('Alasan'),
                      subtitle: Text(item['reason'] as String),
                    ),
                    for (final (key, title) in _fields)
                      ListTile(
                        title: Text(title),
                        subtitle: Text(
                          reportMoney((item['proposed'] as Json)[key]),
                        ),
                      ),
                    if (widget.scope.role == 'owner' &&
                        item['status'] == 'pending')
                      FilledButton(
                        onPressed: _busy ? null : () => _approve(item),
                        child: const Text('Tinjau persetujuan'),
                      ),
                  ],
                ),
              if (_offset > 0)
                TextButton(
                  onPressed: _busy ? null : () => _load(_offset - 20),
                  child: const Text('Halaman sebelumnya'),
                ),
              if (page['nextOffset'] case final int next)
                TextButton(
                  onPressed: _busy ? null : () => _load(next),
                  child: const Text('Halaman berikutnya'),
                ),
            ],
          );
        },
      ),
    ),
  );

  static const _fields = [
    ('caneRupiah', 'Biaya tebu'),
    ('operationalRupiah', 'Biaya operasional'),
    ('ingredientRupiah', 'Biaya bahan'),
    ('otherRupiah', 'Biaya lain'),
  ];
}
