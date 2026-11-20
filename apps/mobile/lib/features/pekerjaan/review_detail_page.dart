import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';

import 'review_api.dart';
import 'manual_note_form.dart';
import 'intake_lot_dialog.dart';
import 'stock_reconciliation_dialog.dart';

class ReviewDetailPage extends StatefulWidget {
  const ReviewDetailPage({
    required this.api,
    required this.taskId,
    this.onNavigate,
    super.key,
  });
  final ValueChanged<NiraTab>? onNavigate;
  final ReviewApi api;
  final String taskId;

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<ReviewDetailPage> {
  late String _taskId = widget.taskId;
  late Future<Json> _task = _load();
  String? _asset;
  List<Json> _evidence = [];
  bool _saving = false;
  String? _retrySignature;
  String? _retryKey;
  final Set<String> _reviewOpened = {};

  Future<Json> _load() async {
    final taskId = _taskId;
    final task = await widget.api.detail(taskId);
    final revision = task['revision_id'];
    if (mounted && revision is String && _reviewOpened.add(revision)) {
      unawaited(_markNotificationRead(taskId, revision));
    }
    return task;
  }

  Future<void> _markNotificationRead(String taskId, String revision) async {
    try {
      await widget.api.markNotificationRead(taskId, revision);
    } catch (_) {
      _reviewOpened.remove(revision);
    }
  }

  Future<void> _change(Json task, String action, Json values) async {
    final signature = jsonEncode([task['revision_id'], action, values]);
    if (_retrySignature != signature) {
      _retrySignature = signature;
      _retryKey = ReviewApi.actionKey();
    }
    setState(() => _saving = true);
    try {
      final outcome = await widget.api.change(
        task,
        action,
        values,
        key: _retryKey!,
      );
      if (!mounted) return;
      _retrySignature = null;
      setState(() {
        if (action == 'reconcile') {
          _taskId = outcome['task_id'] as String;
          _asset = null;
          _evidence = [];
        }
        _task = _load();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perubahan tersimpan.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ReviewApiError
                ? error.message
                : 'Perubahan belum dapat dipastikan. Coba lagi.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(Json task, String path, Json value) async {
    final numeric = value['unit'] == 'kg' || path.endsWith('.brix');
    var input = '${value['normalized_value'] ?? value['raw_value'] ?? ''}';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koreksi nilai'),
        content: TextFormField(
          initialValue: input,
          onChanged: (text) => input = text,
          decoration: InputDecoration(labelText: path.split('.').last),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final parsed = numeric
        ? num.tryParse(result.trim().replaceAll(',', '.'))
        : result.trim();
    if (parsed == null || parsed == '' || (parsed is num && !parsed.isFinite)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nilai koreksi belum valid.')),
      );
      return;
    }
    await _change(task, 'draft', {'field_path': path, 'value': parsed});
  }

  Future<void> _return(Json task) async {
    var reason = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kembalikan untuk koreksi'),
        content: TextField(
          onChanged: (value) => reason = value,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Alasan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.trim().isNotEmpty) {
                Navigator.pop(context, reason.trim());
              }
            },
            child: const Text('Kembalikan'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    await _change(task, 'return', {
      'reason_code': 'NEEDS_CORRECTION',
      'comment': result,
      'request_operator_follow_up': true,
    });
  }

  Future<void> _validate(Json task) async {
    final values = <String, dynamic>{'decision': 'VALIDATED'};
    if (task['document_type'] == 'TRUCK_ARRIVAL_NOTE') {
      final selected = await showDialog<Json>(
        context: context,
        builder: (context) => IntakeLotDialog(api: widget.api, taskId: _taskId),
      );
      if (!mounted || selected == null) return;
      values['lot_id'] = selected['id'];
      values['supplier_id'] = selected['supplierId'];
    } else if (task['document_type'] == 'PRODUCTION_NOTE') {
      final extraction = task['extraction'] as Json?;
      final blocks = (extraction?['cane_blocks'] as List? ?? []).cast<Json>();
      final labels = [
        for (final block in blocks)
          if (block['cane_label'] case {
            'status': 'READ',
            'normalized_value': final String label,
          } when label.trim().isNotEmpty)
            label.trim(),
      ];
      if (labels.length != blocks.length ||
          labels.isEmpty ||
          labels.toSet().length != labels.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lengkapi label tebu yang unik pada setiap blok.'),
          ),
        );
        return;
      }
      final booked = (task['milling'] as List? ?? [])
          .cast<Json>()
          .map((item) => item['cane_label'])
          .toSet();
      final mappings = <Json>[];
      final selectedLots = <String>{};
      for (final label in labels.where((label) => !booked.contains(label))) {
        final mapping = await showDialog<Json>(
          context: context,
          builder: (context) => IntakeLotDialog(
            api: widget.api,
            taskId: _taskId,
            millingLabel: label,
            excludedLots: selectedLots,
          ),
        );
        if (!mounted || mapping == null) return;
        mappings.add(mapping);
        selectedLots.add(mapping['lot_id'] as String);
      }
      values['milling'] = mappings;
    }
    await _change(task, 'validate', values);
  }

  Future<void> _reconcile(Json task) async {
    final values = await showDialog<Json>(
      context: context,
      builder: (context) => StockReconciliationDialog(
        intake: task['intake'] as Json?,
        milling: (task['milling'] as List? ?? []).cast<Json>(),
      ),
    );
    if (mounted && values != null) await _change(task, 'reconcile', values);
  }

  @override
  Widget build(BuildContext context) => NiraPageScaffold(
    onNavigate: widget.onNavigate == null
        ? null
        : (tab) {
            if (!_saving) widget.onNavigate!(tab);
          },
    tab: NiraTab.pengaturan,
    title: const Text('Detail nota'),
    actions: [
      IconButton(
        tooltip: 'Muat ulang',
        onPressed: _saving
            ? null
            : () => setState(() {
                _task = _load();
              }),
        icon: const Icon(Icons.refresh),
      ),
    ],
    body: FutureBuilder<Json>(
      future: _task,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NiraLoading(label: 'Memuat detail nota…');
        }
        if (!snapshot.hasData) {
          final error = snapshot.error;
          return Center(
            child: Text(
              error is ReviewApiError ? error.message : 'Gagal memuat nota.',
            ),
          );
        }
        final task = snapshot.requireData;
        final currentAsset = task['media_asset_id'] as String;
        final asset = _asset ?? currentAsset;
        final actions = task['actions'] as List;
        final confirmation = task['operator_confirmation'] as Json?;
        final intake = task['intake'] as Json?;
        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: niraPageInset(context),
            vertical: NiraSpace.lg,
          ),
          children: [
            Text(
              documentType(task['document_type']),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${task['sender_name']} · Revisi ${task['version']}'),
            Text('Status: ${task['status']}'),
            if (intake != null)
              Text('Stok tebu tercatat: ${intake['net_weight_kg']} kg'),
            for (final item in (task['milling'] as List? ?? []).cast<Json>())
              Text(
                '${item['cane_label']} · Nira tercatat ${item['juice_produced_liters']} L',
              ),
            for (final entry
                in (task['reconciliations'] as List? ?? []).cast<Json>())
              ListTile(
                title: Text(
                  'Revisi ${entry['revision_version']} · ${entry['quantity_before']} → ${entry['quantity_after']} ${entry['material'] == 'sugarcane' ? 'kg' : 'L'}',
                ),
                subtitle: Text('${entry['reason']}'),
              ),
            if (confirmation != null)
              Text(
                'Dikonfirmasi ${confirmation['confirmed_by']} pada revisi ${confirmation['version']}',
              ),
            const SizedBox(height: 12),
            _Photo(
              key: ValueKey(asset),
              api: widget.api,
              taskId: _taskId,
              asset: asset,
              evidence: _evidence,
            ),
            Text(
              'Hasil ekstraksi',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final issue in (task['issues'] as List).cast<Json>())
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('${issue['message']}'),
                dense: true,
              ),
            if (actions.contains('MANUAL_ENTRY'))
              ManualNoteForm(
                document: task['document_type'] as String,
                saving: _saving,
                onSave: (values) => _change(task, 'manual-draft', values),
              ),
            for (final (path, field) in _fields(task['extraction']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(path),
                subtitle: Text(
                  '${field['normalized_value'] ?? field['raw_value'] ?? '—'} ${field['unit'] ?? ''}\n'
                  '${field['status']} · ${field['source']}',
                ),
                onTap:
                    field['evidence'] is List &&
                        (field['evidence'] as List).isNotEmpty
                    ? () {
                        final evidence = field['evidence'] as List;
                        final match = evidence.first as Json;
                        setState(() {
                          _asset = match['asset_id'] as String;
                          _evidence = evidence.cast<Json>();
                        });
                      }
                    : null,
                trailing: actions.contains('CORRECT')
                    ? IconButton(
                        tooltip: 'Koreksi $path',
                        onPressed: _saving
                            ? null
                            : () => _edit(task, path, field),
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
            Text(
              'Riwayat revisi',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final revision in (task['revisions'] as List).cast<Json>())
              ListTile(
                title: Text('Revisi ${revision['version']}'),
                subtitle: Text(
                  '${revision['processing_status']} · ${revision['operator_status']}',
                ),
                trailing: const Icon(Icons.image_outlined),
                onTap: () => setState(() {
                  _asset = revision['media_asset_id'] as String;
                  _evidence = [];
                }),
              ),
            if ((task['audit'] as List?)?.isNotEmpty ?? false)
              ExpansionTile(
                title: const Text('Jejak audit'),
                children: [
                  for (final event in (task['audit'] as List).cast<Json>())
                    ListTile(
                      title: Text('${event['action']}'),
                      subtitle: Text('${event['created_at']}'),
                    ),
                ],
              ),
            if (_saving)
              const NiraLoading(label: 'Menyimpan nota…', compact: true),
            if (actions.contains('VALIDATE'))
              FilledButton(
                onPressed: _saving ? null : () => _validate(task),
                child: const Text('Validasi revisi ini'),
              ),
            if (actions.contains('RECONCILE'))
              OutlinedButton(
                onPressed: _saving ? null : () => _reconcile(task),
                child: const Text('Koreksi stok nota sah'),
              ),
            if (actions.contains('RETURN'))
              OutlinedButton(
                onPressed: _saving ? null : () => _return(task),
                child: const Text('Kembalikan'),
              ),
          ],
        );
      },
    ),
  );
}

Iterable<(String, Json)> _fields(Object? data, [String base = '']) sync* {
  if (data is Json &&
      data.containsKey('normalized_value') &&
      data.containsKey('evidence')) {
    yield (base, data);
  } else if (data is Json) {
    for (final entry in data.entries) {
      yield* _fields(
        entry.value,
        base.isEmpty ? entry.key : '$base.${entry.key}',
      );
    }
  } else if (data is List) {
    for (final (index, value) in data.indexed) {
      yield* _fields(value, '$base.$index');
    }
  }
}

class _Photo extends StatefulWidget {
  const _Photo({
    required this.api,
    required this.taskId,
    required this.asset,
    required this.evidence,
    super.key,
  });
  final ReviewApi api;
  final String taskId;
  final String asset;
  final List<Json> evidence;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  late final Future<(Uint8List, double)> _image = _load();

  Future<(Uint8List, double)> _load() async {
    final bytes = await widget.api.photo(widget.taskId, widget.asset);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 640,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        return (bytes, frame.image.width / frame.image.height);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(Uint8List, double)>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Foto asli belum dapat dimuat.');
      if (!snapshot.hasData)
        return const NiraLoading(label: 'Memuat foto nota…');
      final (bytes, ratio) = snapshot.requireData;
      return AspectRatio(
        aspectRatio: ratio,
        child: LayoutBuilder(
          builder: (context, size) => Stack(
            children: [
              Positioned.fill(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  cacheWidth: 640,
                  semanticLabel: 'Foto asli nota',
                ),
              ),
              for (final box in widget.evidence.where(
                (item) =>
                    item['asset_id'] == widget.asset &&
                    item['coordinate_space'] == 'ORIGINAL_IMAGE_NORMALIZED',
              ))
                _box(box, size),
            ],
          ),
        ),
      );
    },
  );

  Widget _box(Json box, BoxConstraints size) {
    final dims = (box['bbox'] as List).cast<num>();
    return Positioned(
      left: dims[0] * size.maxWidth,
      top: dims[1] * size.maxHeight,
      width: dims[2] * size.maxWidth,
      height: dims[3] * size.maxHeight,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: Colors.orange, width: 2),
          ),
        ),
      ),
    );
  }
}
