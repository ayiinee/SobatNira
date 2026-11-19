import '../laporan/connected_profit_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../auth/login_pages.dart';
import '../pekerjaan/pekerjaan_page.dart';
import '../pekerjaan/review_api.dart';
import 'production_catalog_page.dart';
import 'production_lot_editor.dart';
import 'lot_closure_page.dart';
import 'juice_transfer_page.dart';

typedef FactoryHomeBuilder =
    Widget Function(
      ReviewApi api,
      List<FactoryScope> factories,
      FactoryScope scope,
      ValueChanged<FactoryScope> selectFactory,
      VoidCallback signOut,
    );

class ConnectedKloterPage extends StatefulWidget {
  const ConnectedKloterPage({
    super.key,
    this.signIn = ReviewApi.signIn,
    this.invalidConfiguration = const [],
    this.homeBuilder,
  });
  final Future<ReviewApi> Function(String email, String password) signIn;
  final List<String> invalidConfiguration;
  final FactoryHomeBuilder? homeBuilder;

  @override
  State<ConnectedKloterPage> createState() => _ConnectedKloterPageState();
}

class _ConnectedKloterPageState extends State<ConnectedKloterPage> {
  final _searchInput = TextEditingController();
  ReviewApi? _api;
  List<FactoryScope>? _factories;
  FactoryScope? _scope;
  Future<Json>? _lots;
  String _search = '';
  int _offset = 0;
  bool _showLogin = false;
  bool _signingIn = false;
  bool _checkingAccess = false;
  String? _loginMessage;

  @override
  void dispose() {
    _api?.close();
    _searchInput.dispose();
    super.dispose();
  }

  Future<void> _signIn(String email, String password) async {
    if (_signingIn || _api != null) return;
    setState(() {
      _signingIn = true;
      _loginMessage = null;
    });
    try {
      final api = await widget.signIn(email, password);
      if (!mounted) {
        api.close();
        return;
      }
      api.onSessionExpired = () => scheduleMicrotask(() {
        if (mounted && identical(_api, api)) _endSession(expired: true);
      });
      _api = api;
      unawaited(_checkAccess(api));
    } catch (error) {
      if (mounted) {
        setState(() {
          _loginMessage = switch (error) {
            ReviewApiError(status: 429) =>
              'Terlalu banyak percobaan. Tunggu sebentar sebelum mencoba lagi.',
            ReviewApiError(authCode: 'invalid_credentials') =>
              'Email atau kata sandi tidak cocok.',
            ReviewApiError(authCode: 'email_not_confirmed') =>
              'Email belum dikonfirmasi. Periksa kotak masuk atau hubungi pengelola pabrik.',
            ReviewApiError(authCode: 'user_banned') =>
              'Akun ini tidak bisa digunakan. Hubungi pengelola pabrik.',
            ReviewApiError(status: >= 500) || TimeoutException() =>
              'Belum bisa masuk. Periksa koneksi dan coba lagi.',
            _ => 'Belum bisa masuk. Coba lagi atau hubungi pengelola pabrik.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _checkAccess(ReviewApi api) async {
    if (_checkingAccess) return;
    setState(() => _checkingAccess = true);
    try {
      final factories = await api.factories();
      if (!mounted || !identical(_api, api)) return;
      setState(() {
        _factories = factories;
        _scope = factories.firstOrNull;
        if (widget.homeBuilder == null) _load();
      });
    } catch (_) {
      // A transient failure leaves access unloaded so the user can retry.
      // ReviewApi handles expired sessions before returning a 401 error.
    } finally {
      if (mounted && identical(_api, api)) {
        setState(() => _checkingAccess = false);
      }
    }
  }

  void _endSession({bool expired = false}) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _api?.close();
    _searchInput.clear();
    setState(() {
      _api = null;
      _factories = null;
      _scope = null;
      _lots = null;
      _search = '';
      _offset = 0;
      _checkingAccess = false;
      _showLogin = true;
      _loginMessage = expired ? 'Sesi berakhir. Masuk kembali.' : null;
    });
  }

  void _load() {
    final scope = _scope;
    _lots = scope == null
        ? null
        : _api!.lots(scope, offset: _offset, search: _search);
    // A fast response can fail before the next frame attaches FutureBuilder.
    _lots?.ignore();
  }

  void _changeSearch(String value) => setState(() {
    _search = value.trim();
    _offset = 0;
    _load();
  });

  Future<void> _openCatalog(FactoryScope scope, ProductionCatalog kind) async {
    final api = _api!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ProductionCatalogPage(api: api, scope: scope, kind: kind),
      ),
    );
    if (mounted &&
        identical(_api, api) &&
        kind != ProductionCatalog.operators) {
      setState(_load);
    }
  }

  Future<void> _createLot(FactoryScope scope) async {
    final api = _api!;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductionLotEditor(api: api, scope: scope),
      ),
    );
    if (mounted && identical(_api, api) && saved == true) {
      setState(() {
        _offset = 0;
        _load();
      });
    }
  }

  Future<void> _openLot(FactoryScope scope, Json lot) async {
    final api = _api!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ConnectedLotDetail(api: api, scope: scope, lot: lot),
      ),
    );
    if (mounted && identical(_api, api)) setState(_load);
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
  Widget build(BuildContext context) {
    final api = _api;
    if (widget.invalidConfiguration.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('SobatNira')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(NiraSpace.lg),
            children: [
              const Text('Layanan masuk belum dikonfigurasi.'),
              const Text('Hubungi pengelola SobatNira untuk bantuan.'),
              Text('Periksa ${widget.invalidConfiguration.join(', ')}.'),
            ],
          ),
        ),
      );
    }
    if (api == null) {
      return _showLogin
          ? LoginFormPage(
              busy: _signingIn,
              message: _loginMessage,
              onSubmit: _signIn,
              onBack: () => setState(() {
                _showLogin = false;
                _loginMessage = null;
              }),
            )
          : LoginWelcomePage(
              onContinue: () => setState(() => _showLogin = true),
            );
    }
    final scope = _scope;
    final buildHome = widget.homeBuilder;
    if (scope != null && buildHome != null) {
      return buildHome(api, _factories!, scope, (selected) {
        if (selected != _scope && _factories!.contains(selected)) {
          setState(() => _scope = selected);
        }
      }, _endSession);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_scope == null ? 'Akses pabrik' : 'Kloter'),
        actions: [
          TextButton(onPressed: _endSession, child: const Text('Keluar')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NiraSpace.lg),
          children: _factories == null ? _accessPending(api) : _production(),
        ),
      ),
    );
  }

  List<Widget> _accessPending(ReviewApi api) => _checkingAccess
      ? [
          const LinearProgressIndicator(),
          const SizedBox(height: NiraSpace.lg),
          Semantics(
            liveRegion: true,
            child: const Text('Memeriksa akses pabrik…'),
          ),
        ]
      : [
          Semantics(
            liveRegion: true,
            child: const Text(
              'Akses pabrik belum dapat diperiksa. Periksa koneksi dan coba lagi.',
            ),
          ),
          const SizedBox(height: NiraSpace.lg),
          NiraButton('Coba lagi', () => _checkAccess(api), shadow: false),
        ];

  List<Widget> _production() {
    final scope = _scope;
    if (scope == null) {
      return [
        Semantics(
          liveRegion: true,
          child: const Text('Akun ini belum memiliki akses pabrik aktif.'),
        ),
        const SizedBox(height: NiraSpace.sm),
        const Text('Hubungi pengelola pabrik untuk mendapatkan akses.'),
      ];
    }
    return [
      DropdownButtonFormField<FactoryScope>(
        initialValue: scope,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Pabrik'),
        items: [
          for (final factory in _factories!)
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
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ConnectedProfitPage(api: _api!, scope: scope),
          ),
        ),
        icon: const Icon(Icons.assessment_outlined),
        label: const Text('Laporan laba'),
      ),
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
          NiraPagination(
            page: _offset ~/ limit + 1,
            pageCount: (total / limit).ceil(),
            onPrevious: _offset > 0
                ? () => setState(() {
                    _offset -= limit;
                    _load();
                  })
                : null,
            onNext: _offset + limit < total
                ? () => setState(() {
                    _offset += limit;
                    _load();
                  })
                : null,
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
