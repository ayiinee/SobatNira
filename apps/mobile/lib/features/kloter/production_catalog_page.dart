import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import '../pekerjaan/review_api.dart';
import '../pekerjaan/production_api.dart';
import '../pengaturan/operator_history_page.dart';
import '../pengaturan/settings_widgets.dart';

class ProductionCatalogPage extends StatefulWidget {
  const ProductionCatalogPage({
    super.key,
    required this.api,
    required this.scope,
    required this.kind,
    this.selectSupplier = false,
    this.masterKind,
    this.onNavigate,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final ProductionCatalog kind;
  final bool selectSupplier;
  final String? masterKind;
  final ValueChanged<NiraTab>? onNavigate;

  @override
  State<ProductionCatalogPage> createState() => _ProductionCatalogPageState();
}

class _ProductionCatalogPageState extends State<ProductionCatalogPage> {
  final _pageHeight = NiraPageHeight();
  final _search = TextEditingController();
  int _offset = 0;
  String _query = '';
  bool? _active;
  late Future<Json> _page = _fetch();

  Future<Json> _fetch() => widget.masterKind != null
      ? MasterDataApi(widget.api).list(widget.scope, widget.masterKind!)
      : widget.api.catalog(
          widget.scope,
          widget.kind,
          offset: _offset,
          search: _query,
          active: widget.selectSupplier ? true : _active,
        );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _isOperator => widget.kind == ProductionCatalog.operators;

  void _openHistory(Json item) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OperatorHistoryPage(
          api: widget.api,
          scope: widget.scope,
          operatorId: item['id'] as String,
          phone: item['phoneE164'] as String,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
  }

  void _reload({bool reset = false}) => setState(() {
    if (reset) _offset = 0;
    _page = _fetch();
  });

  Future<void> _edit([Json? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CatalogEditor(
        api: widget.api,
        scope: widget.scope,
        kind: widget.kind,
        item: item,
        masterKind: widget.masterKind,
      ),
    );
    if (mounted && saved == true) _reload(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.selectSupplier
        ? 'Pilih pemasok aktif'
        : widget.kind.label;
    final subtitle =
        '${widget.scope.factoryName} \u00b7 ${widget.scope.tenantName}';
    final children = <Widget>[
      Container(
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
            TextField(
              controller: _search,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Cari ${widget.kind.itemLabel}',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: 'Cari',
                  icon: const Icon(Icons.search, size: 22),
                  onPressed: () => _submitSearch(_search.text),
                ),
              ),
              onSubmitted: _submitSearch,
            ),
            if (!widget.selectSupplier)
              DropdownButtonFormField<String>(
                initialValue: 'all',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua status')),
                  DropdownMenuItem(value: 'active', child: Text('Aktif')),
                  DropdownMenuItem(value: 'inactive', child: Text('Nonaktif')),
                ],
                onChanged: (value) {
                  _active = switch (value) {
                    'active' => true,
                    'inactive' => false,
                    _ => null,
                  };
                  _reload(reset: true);
                },
              ),
          ],
        ),
      ),
      if (!widget.selectSupplier) ...[
        const SizedBox(height: NiraSpace.lg),
        FilledButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add, size: 20),
          label: Text(
            'Tambah ${widget.kind.itemLabel}',
            textAlign: TextAlign.center,
          ),
        ),
      ],
      const SizedBox(height: NiraSpace.xl),
      NiraPagedFutureBuilder<Json>(
        future: _page,
        page: _offset,
        dataset: (widget.scope.factoryId, widget.kind, _query, _active),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const NiraLoading(label: 'Memuat daftar…');
          }
          if (snapshot.hasError) {
            return _notice(
              icon: Icons.error_outline,
              label: snapshot.error is ReviewApiError
                  ? (snapshot.error as ReviewApiError).message
                  : 'Data gagal dimuat.',
              action: TextButton(
                onPressed: _reload,
                child: const Text('Coba lagi'),
              ),
            );
          }
          final page = snapshot.requireData;
          final items = (page['items'] as List).cast<Json>();
          final limit = page['limit'] as int;
          final total = page['total'] as int;
          return Column(
            children: [
              NiraPageBody(
                height: _pageHeight,
                firstPage: _offset == 0,
                child: items.isEmpty
                    ? _notice(
                        icon: Icons.inbox_outlined,
                        label: 'Data tidak ditemukan.',
                        detail: _query.isNotEmpty || _active != null
                            ? 'Ubah kata kunci atau filter status.'
                            : null,
                      )
                    : Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: Colors.white,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: niraLine),
                          borderRadius: BorderRadius.circular(niraRadius * 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, item) in items.indexed) ...[
                              if (index > 0)
                                const Divider(height: 1, color: niraLine),
                              _catalogRow(item),
                            ],
                          ],
                        ),
                      ),
              ),
              if (_offset > 0 || total > limit)
                NiraPagination(
                  page: _offset ~/ limit + 1,
                  pageCount: (total / limit).ceil(),
                  onPrevious: _offset > 0
                      ? () {
                          _offset -= limit;
                          _reload();
                        }
                      : null,
                  onNext: _offset + limit < total
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
      const SizedBox(height: NiraSpace.md),
      TextButton.icon(
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
        label: const Text('Muat ulang'),
      ),
    ];
    if (widget.onNavigate case final navigate?) {
      return SettingsPageFrame(
        title: title,
        subtitle: subtitle,
        onNavigate: navigate,
        children: children,
      );
    }
    return NiraPageScaffold(
      title: Text(title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(subtitle, style: niraText(NiraType.caption, color: niraLeaf)),
            const SizedBox(height: NiraSpace.lg),
            ...children,
          ],
        ),
      ),
    );
  }

  void _submitSearch(String value) {
    _query = value.trim();
    _reload(reset: true);
  }

  Widget _catalogRow(Json item) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: NiraSpace.md),
    minVerticalPadding: NiraSpace.md,
    horizontalTitleGap: NiraSpace.sm,
    title: Text(
      item[_isOperator ? 'displayName' : 'name'] as String,
      style: niraText(NiraType.body, weight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: NiraSpace.xs),
      child: Text(
        [
          if (_isOperator) item['phoneE164'] as String,
          if (item['code'] != null) '${item['code']}',
          item['isActive'] == true ? 'Aktif' : 'Nonaktif',
        ].join(' · '),
        style: niraText(NiraType.caption, color: niraLeaf),
      ),
    ),
    trailing: _isOperator
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: NiraSpace.sm,
            children: [
              IconButton(
                tooltip: 'Edit operator',
                onPressed: () => _edit(item),
                color: niraGreen,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Riwayat operator',
                onPressed: () => _openHistory(item),
                color: niraGreen,
                icon: const Icon(Icons.history, size: 20),
              ),
            ],
          )
        : Icon(
            widget.selectSupplier ? Icons.chevron_right : Icons.edit_outlined,
            color: niraGreen,
            size: 20,
          ),
    onTap: () {
      if (widget.selectSupplier) {
        Navigator.pop(context, item);
      } else {
        _edit(item);
      }
    },
  );

  Widget _notice({
    required IconData icon,
    required String label,
    String? detail,
    Widget? action,
  }) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: NiraSpace.xl),
      child: Column(
        spacing: NiraSpace.sm,
        children: [
          Icon(icon, color: niraLeaf),
          Text(label, textAlign: TextAlign.center),
          if (detail != null)
            Text(
              detail,
              textAlign: TextAlign.center,
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          ?action,
        ],
      ),
    ),
  );
}

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({
    required this.api,
    required this.scope,
    required this.kind,
    this.item,
    this.masterKind,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final ProductionCatalog kind;
  final Json? item;
  final String? masterKind;

  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _form = GlobalKey<FormState>();
  bool get _isOperator => widget.kind == ProductionCatalog.operators;
  String get _nameField => _isOperator ? 'displayName' : 'name';

  late final _name = TextEditingController(
    text: widget.item?[_nameField] as String?,
  );
  final _code = TextEditingController();
  final _phone = TextEditingController();
  late bool _active = widget.item?['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final item = widget.item;
    final name = _name.text.trim();
    final values = <String, dynamic>{
      if (!_isOperator || item == null || name != item[_nameField])
        _nameField: name,
      if (item != null && (!_isOperator || _active != item['isActive']))
        'isActive': _active,
      if (item == null && _isOperator) 'phoneE164': _phone.text.trim(),
      if (item == null && widget.kind == ProductionCatalog.caneTypes)
        'code': _code.text.trim(),
    };
    if (values.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.masterKind != null) {
        await MasterDataApi(
          widget.api,
        ).create(widget.scope, widget.masterKind!, values);
      } else {
        await widget.api.saveCatalog(
          widget.scope,
          widget.kind,
          values,
          id: item?['id'] as String?,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            ReviewApiError(status: 409) when _isOperator =>
              'Nomor WhatsApp sudah terdaftar.',
            ReviewApiError(status: 409)
                when widget.kind == ProductionCatalog.caneTypes =>
              'Kode jenis tebu sudah terdaftar. Gunakan kode lain.',
            ReviewApiError() => error.message,
            _ =>
              'Penyimpanan belum terkonfirmasi. Tutup form dan muat ulang daftar sebelum mencoba lagi.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        '${widget.item == null ? 'Tambah' : 'Edit'} ${widget.kind.itemLabel}',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: NiraSpace.md,
          children: [
            if (widget.kind == ProductionCatalog.caneTypes)
              if (widget.item == null)
                TextFormField(
                  controller: _code,
                  enabled: !_saving,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Kode jenis tebu',
                  ),
                  validator: (value) =>
                      RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(value!.trim())
                      ? null
                      : 'Gunakan huruf, angka, tanda hubung, atau garis bawah.',
                )
              else
                Text('Kode ${widget.item!['code']}'),
            if (_isOperator && widget.item == null)
              TextFormField(
                controller: _phone,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Nomor WhatsApp',
                  hintText: '+6281234567890',
                ),
                validator: (value) =>
                    RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value!.trim())
                    ? null
                    : 'Masukkan nomor dengan kode negara, misalnya +6281234567890.',
              ),
            if (_isOperator && widget.item != null)
              Text(widget.item!['phoneE164'] as String),
            TextFormField(
              controller: _name,
              enabled: !_saving,
              maxLength: _isOperator ? 100 : 200,
              decoration: const InputDecoration(labelText: 'Nama'),
              validator: (value) => value!.trim().isEmpty ? 'Isi nama.' : null,
            ),
            if (widget.item != null)
              SwitchListTile(
                title: const Text('Aktif'),
                subtitle: _isOperator
                    ? const Text(
                        'Nomor nonaktif ditolak saat mengirim nota baru.',
                      )
                    : null,
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
            if (_saving)
              const NiraLoading(label: 'Menyimpan data…', compact: true),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}
