import 'package:flutter/material.dart';

import '../pekerjaan/review_api.dart';

class ProductionCatalogPage extends StatefulWidget {
  const ProductionCatalogPage({
    super.key,
    required this.api,
    required this.scope,
    required this.kind,
    this.selectSupplier = false,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final ProductionCatalog kind;
  final bool selectSupplier;

  @override
  State<ProductionCatalogPage> createState() => _ProductionCatalogPageState();
}

class _ProductionCatalogPageState extends State<ProductionCatalogPage> {
  final _search = TextEditingController();
  int _offset = 0;
  String _query = '';
  bool? _active;
  late Future<Json> _page = _fetch();

  Future<Json> _fetch() => widget.api.catalog(
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
      ),
    );
    if (mounted && saved == true) _reload(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.selectSupplier ? 'Pilih pemasok aktif' : widget.kind.label,
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${widget.scope.factoryName} · ${widget.scope.tenantName}'),
          TextField(
            controller: _search,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Cari ${widget.kind.label.toLowerCase()}',
              suffixIcon: IconButton(
                tooltip: 'Cari',
                icon: const Icon(Icons.search),
                onPressed: () {
                  _query = _search.text.trim();
                  _reload(reset: true);
                },
              ),
            ),
            onSubmitted: (value) {
              _query = value.trim();
              _reload(reset: true);
            },
          ),
          if (!widget.selectSupplier)
            DropdownButtonFormField<String>(
              initialValue: 'all',
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
          if (!widget.selectSupplier)
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text('Tambah ${widget.kind.label.toLowerCase()}'),
            ),
          FutureBuilder<Json>(
            future: _page,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text(
                      snapshot.error is ReviewApiError
                          ? (snapshot.error as ReviewApiError).message
                          : 'Data gagal dimuat.',
                    ),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                );
              }
              final page = snapshot.requireData;
              final items = (page['items'] as List).cast<Json>();
              final limit = page['limit'] as int;
              return Column(
                children: [
                  if (items.isEmpty)
                    const ListTile(title: Text('Data tidak ditemukan.')),
                  for (final item in items)
                    ListTile(
                      title: Text(item['name'] as String),
                      subtitle: Text(
                        [
                          if (item['code'] != null) '${item['code']}',
                          item['isActive'] == true ? 'Aktif' : 'Nonaktif',
                        ].join(' · '),
                      ),
                      trailing: Icon(
                        widget.selectSupplier
                            ? Icons.chevron_right
                            : Icons.edit_outlined,
                      ),
                      onTap: () {
                        if (widget.selectSupplier) {
                          Navigator.pop(context, item);
                        } else {
                          _edit(item);
                        }
                      },
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _offset > 0
                            ? () {
                                _offset -= limit;
                                _reload();
                              }
                            : null,
                        child: const Text('Sebelumnya'),
                      ),
                      TextButton(
                        onPressed: _offset + limit < (page['total'] as int)
                            ? () {
                                _offset += limit;
                                _reload();
                              }
                            : null,
                        child: const Text('Berikutnya'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          TextButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
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
  });
  final ReviewApi api;
  final FactoryScope scope;
  final ProductionCatalog kind;
  final Json? item;

  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.item?['name'] as String?,
  );
  final _code = TextEditingController();
  late bool _active = widget.item?['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveCatalog(widget.scope, widget.kind, {
        'name': _name.text.trim(),
        if (widget.item != null) 'isActive': _active,
        if (widget.kind == ProductionCatalog.caneTypes && widget.item == null)
          'code': _code.text.trim(),
      }, id: widget.item?['id'] as String?);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ReviewApiError
              ? error.status == 409
                    ? 'Kode jenis tebu sudah terdaftar. Gunakan kode lain.'
                    : error.message
              : 'Penyimpanan belum terkonfirmasi. Tutup form dan muat ulang daftar sebelum mencoba lagi.',
        );
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
        '${widget.item == null ? 'Tambah' : 'Edit'} ${widget.kind.label.toLowerCase()}',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            TextFormField(
              controller: _name,
              enabled: !_saving,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Nama'),
              validator: (value) => value!.trim().isEmpty ? 'Isi nama.' : null,
            ),
            if (widget.item != null)
              SwitchListTile(
                title: const Text('Aktif'),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
            if (_saving) const LinearProgressIndicator(),
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
