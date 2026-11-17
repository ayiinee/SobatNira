import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../pekerjaan/pekerjaan_page.dart';
import '../pekerjaan/review_api.dart';
import 'production_catalog_page.dart';
import 'production_lot_editor.dart';
import 'lot_closure_page.dart';
import 'juice_transfer_page.dart';

class ConnectedKloterPage extends StatefulWidget {
  const ConnectedKloterPage({
    super.key,
    this.signIn = ReviewApi.signIn,
    this.invalidConfiguration = const [],
  });
  final Future<ReviewApi> Function(String email, String password) signIn;
  final List<String> invalidConfiguration;

  @override
  State<ConnectedKloterPage> createState() => _ConnectedKloterPageState();
}

class _ConnectedKloterPageState extends State<ConnectedKloterPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _searchInput = TextEditingController();
  ReviewApi? _api;
  List<FactoryScope> _factories = [];
  FactoryScope? _scope;
  Future<Json>? _lots;
  String _search = '';
  int _offset = 0;
  bool _signingIn = false;
  String? _error;

  @override
  void dispose() {
    _api?.close();
    _email.dispose();
    _password.dispose();
    _searchInput.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    ReviewApi? api;
    try {
      api = await widget.signIn(_email.text.trim(), _password.text);
      final factories = await api.factories();
      if (!mounted) return;
      _password.clear();
      setState(() {
        _api = api;
        _factories = factories;
        _scope = factories.firstOrNull;
        _load();
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ReviewApiError && error.status == 503
              ? error.message
              : 'Gagal masuk. Periksa akun dan koneksi.',
        );
      }
    } finally {
      if (!identical(_api, api)) api?.close();
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _signOut() {
    _api?.close();
    _searchInput.clear();
    setState(() {
      _api = null;
      _factories = [];
      _scope = null;
      _lots = null;
      _search = '';
      _offset = 0;
    });
  }

  void _load() {
    final scope = _scope;
    _lots = scope == null
        ? null
        : _api!.lots(scope, offset: _offset, search: _search);
  }

  void _changeSearch(String value) => setState(() {
    _search = value.trim();
    _offset = 0;
    _load();
  });

  Future<void> _openCatalog(FactoryScope scope, ProductionCatalog kind) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ProductionCatalogPage(api: _api!, scope: scope, kind: kind),
      ),
    );
    if (mounted && kind != ProductionCatalog.operators) setState(_load);
  }

  Future<void> _createLot(FactoryScope scope) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductionLotEditor(api: _api!, scope: scope),
      ),
    );
    if (mounted && saved == true) {
      setState(() {
        _offset = 0;
        _load();
      });
    }
  }

  Future<void> _openLot(FactoryScope scope, Json lot) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ConnectedLotDetail(api: _api!, scope: scope, lot: lot),
      ),
    );
    if (mounted) setState(_load);
  }

  void _openReview(FactoryScope scope) {
    final api = _api!;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(scope.factoryName)),
          body: SafeArea(
            child: PekerjaanPage(
              api: api,
              factoryId: scope.factoryId,
              active: true,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_api == null ? 'SobatNira' : 'Kloter'),
      actions: [
        if (_api != null)
          TextButton(onPressed: _signOut, child: const Text('Keluar')),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(NiraSpace.lg),
        children: widget.invalidConfiguration.isNotEmpty
            ? [
                Text(
                  'Periksa konfigurasi Flutter ${widget.invalidConfiguration.join(', ')}.',
                ),
              ]
            : _api == null
            ? _login()
            : _production(),
      ),
    ),
  );

  List<Widget> _login() => [
    TextField(
      controller: _email,
      decoration: const InputDecoration(labelText: 'Email'),
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.username],
    ),
    TextField(
      controller: _password,
      decoration: const InputDecoration(labelText: 'Kata sandi'),
      obscureText: true,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) => _signIn(),
    ),
    const SizedBox(height: NiraSpace.lg),
    FilledButton(
      onPressed: _signingIn ? null : _signIn,
      child: Text(_signingIn ? 'Memeriksa akun…' : 'Masuk'),
    ),
    if (_error case final String message) Text(message),
  ];

  List<Widget> _production() {
    final scope = _scope;
    if (scope == null) {
      return [const Text('Akun ini belum memiliki akses pabrik aktif.')];
    }
    return [
      DropdownButtonFormField<FactoryScope>(
        initialValue: scope,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Pabrik'),
        items: [
          for (final factory in _factories)
            DropdownMenuItem(
              value: factory,
              child: Text(
                '${factory.factoryName} · ${factory.tenantName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (factory) => setState(() {
          _scope = factory;
          _offset = 0;
          _load();
        }),
      ),
      const SizedBox(height: NiraSpace.md),
      OutlinedButton.icon(
        onPressed: () => _openReview(scope),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Pekerjaan'),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final kind in ProductionCatalog.values)
            OutlinedButton(
              onPressed: () => _openCatalog(scope, kind),
              child: Text(kind.label),
            ),
        ],
      ),
      FilledButton.icon(
        onPressed: () => _createLot(scope),
        icon: const Icon(Icons.add),
        label: const Text('Tambah kloter'),
      ),
      TextField(
        controller: _searchInput,
        maxLength: 100,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        decoration: InputDecoration(
          labelText: 'Cari kode kloter atau pemasok',
          suffixIcon: IconButton(
            tooltip: 'Cari kloter',
            icon: const Icon(Icons.search),
            onPressed: () => _changeSearch(_searchInput.text),
          ),
        ),
        onSubmitted: _changeSearch,
      ),
      const SizedBox(height: NiraSpace.md),
      FutureBuilder<Json>(
        future: _lots,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return _LoadError(
              error: snapshot.error,
              retry: () => setState(_load),
            );
          }
          return _lotList(scope, snapshot.requireData);
        },
      ),
    ];
  }

  Widget _lotList(FactoryScope scope, Json page) {
    final lots = (page['items'] as List).cast<Json>();
    final limit = page['limit'] as int;
    final total = page['total'] as int;
    return Column(
      children: [
        if (lots.isEmpty)
          const ListTile(title: Text('Belum ada kloter yang ditemukan.')),
        for (final lot in lots)
          Card(
            child: ListTile(
              title: Text(_lotCode(lot)),
              subtitle: Text('${lot['supplierName']} · ${_receivedAt(lot)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLot(scope, lot),
            ),
          ),
        if (_offset > 0 || _offset + limit < total)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _offset > 0
                    ? () => setState(() {
                        _offset -= limit;
                        _load();
                      })
                    : null,
                child: const Text('Sebelumnya'),
              ),
              TextButton(
                onPressed: _offset + limit < total
                    ? () => setState(() {
                        _offset += limit;
                        _load();
                      })
                    : null,
                child: const Text('Berikutnya'),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang kloter'),
        ),
      ],
    );
  }
}

String _lotCode(Json lot) => (lot['displayCode'] ?? lot['id']) as String;

String _receivedAt(Json lot) => DateTime.parse(
  lot['receivedAt'] as String,
).toLocal().toIso8601String().substring(0, 10);

class _ConnectedLotDetail extends StatefulWidget {
  const _ConnectedLotDetail({
    required this.api,
    required this.scope,
    required this.lot,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final Json lot;

  @override
  State<_ConnectedLotDetail> createState() => _ConnectedLotDetailState();
}

class _ConnectedLotDetailState extends State<_ConnectedLotDetail> {
  late var _data = _load();

  Future<void> _transfer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => JuiceTransferPage(
          api: widget.api,
          scope: widget.scope,
          lotId: widget.lot['id'] as String,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _closure() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LotClosurePage(
          api: widget.api,
          scope: widget.scope,
          lotId: widget.lot['id'] as String,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _edit(Json lot) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProductionLotEditor(api: widget.api, scope: widget.scope, lot: lot),
      ),
    );
    if (mounted && saved == true) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<List<Json>> _load() {
    final id = widget.lot['id'] as String;
    final request = Future.wait([
      widget.api.lot(widget.scope, id),
      widget.api.juice(widget.scope, id),
    ]);
    request.ignore();
    return request;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Detail kloter'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang detail',
          onPressed: () => setState(() {
            _data = _load();
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<List<Json>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return _LoadError(
              error: snapshot.error,
              retry: () => setState(() {
                _data = _load();
              }),
            );
          }
          final [lot, stock] = snapshot.requireData;
          return ListView(
            children: [
              ListTile(
                title: const Text('Kode kloter'),
                subtitle: Text(_lotCode(lot)),
                trailing: IconButton(
                  tooltip: 'Edit kloter',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(lot),
                ),
              ),
              ListTile(
                title: const Text('Pabrik'),
                subtitle: Text(widget.scope.factoryName),
              ),
              ListTile(
                title: const Text('Pemasok'),
                subtitle: Text(lot['supplierName'] as String),
              ),
              ListTile(
                title: const Text('Diterima'),
                subtitle: Text(_receivedAt(lot)),
              ),
              ListTile(
                title: const Text('Status kloter'),
                subtitle: Text(
                  lot['status'] == 'closed' ? 'Ditutup' : 'Terbuka',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _closure,
                icon: const Icon(Icons.history),
                label: const Text('Penutupan dan riwayat'),
              ),
              ListTile(
                title: const Text('Berat bersih penerimaan'),
                subtitle: Text(
                  lot['netWeightGrams'] == null
                      ? 'Belum dibukukan'
                      : '${lot['netWeightGrams']} g',
                ),
              ),
              const Divider(),
              ListTile(
                title: const Text('Stok fisik nira'),
                subtitle: Text('${stock['onHandMl']} mL'),
              ),
              ListTile(
                title: const Text('Nira direservasi'),
                subtitle: Text('${stock['reservedMl']} mL'),
              ),
              ListTile(
                title: const Text('Nira tersedia'),
                subtitle: Text('${stock['availableMl']} mL'),
              ),
              OutlinedButton.icon(
                onPressed: _transfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transfer nira'),
              ),
              const Divider(),
              _ApprovedNote(
                title: 'Nota Kedatangan Truk',
                record: lot['intake'] as Json?,
              ),
              _ApprovedNote(
                title: 'Nota Produksi',
                record: lot['milling'] as Json?,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _ApprovedNote extends StatelessWidget {
  const _ApprovedNote({required this.title, required this.record});
  final String title;
  final Json? record;

  @override
  Widget build(BuildContext context) {
    final document = record?['document'] as Json?;
    if (document == null) {
      return ListTile(
        title: Text(title),
        subtitle: const Text('Belum dibukukan'),
      );
    }
    return ExpansionTile(
      title: Text(title),
      subtitle: const Text('Sah dan sudah dibukukan'),
      children: [
        ListTile(
          title: const Text('ID dokumen'),
          subtitle: SelectableText(document['documentId'] as String),
        ),
        if (document['revisionId'] case final String revision)
          ListTile(
            title: const Text('ID revisi'),
            subtitle: SelectableText(revision),
          ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final failure = error;
    final expired = failure is ReviewApiError && failure.status == 401;
    return ListTile(
      title: Text(
        failure is ReviewApiError
            ? failure.message
            : 'Gagal memuat data kloter.',
      ),
      subtitle: expired
          ? const Text('Kembali dan masuk ulang melalui menu Keluar.')
          : null,
      trailing: expired
          ? null
          : TextButton(onPressed: retry, child: const Text('Coba lagi')),
    );
  }
}
