import 'package:flutter/material.dart';

import 'features/beranda/beranda_page.dart';
import 'features/kloter/official_batch_workflow.dart';
import 'features/laporan/connected_profit_page.dart';
import 'features/bantuan/bantuan_page.dart';
import 'features/beranda/quick_action_icon.dart';
import 'features/kloter/connected_kloter_page.dart';
import 'features/kloter/connected_production.dart';
import 'features/kloter/juice_transfer_page.dart';
import 'features/kloter/lot_closure_page.dart';
import 'features/kloter/production_catalog_page.dart';
import 'features/kloter/production_lot_editor.dart';
import 'features/pekerjaan/pekerjaan_page.dart';
import 'features/kloter/demo_production.dart';
import 'features/kloter/kloter_detail_page.dart';
import 'features/kloter/kloter_detail_widgets.dart';
import 'features/kloter/kloter_list_page.dart';
import 'features/laporan/demo_analytics.dart';
import 'features/laporan/laporan_page.dart';
import 'features/laporan/report_detail_page.dart';
import 'features/laporan/report_export_page.dart';
import 'features/laporan/printable_report.dart';
import 'features/pekerjaan/review_api.dart';
import 'features/pengaturan/pengaturan_page.dart';
import 'features/pengaturan/settings_demo.dart';
import 'features/pengaturan/harga_biaya_page.dart';
import 'sobatnira_ui.dart';

void main() => runApp(const SobatNiraApp());

class SobatNiraApp extends StatelessWidget {
  const SobatNiraApp({
    super.key,
    this.connected = connectedMobile,
    this.signIn = ReviewApi.signIn,
    this.configurationErrors,
  });

  final bool connected;
  final Future<ReviewApi> Function(String email, String password) signIn;
  final List<String>? configurationErrors;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SobatNira',
    debugShowCheckedModeBanner: false,
    theme: niraTheme(),
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFF2F2EE),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child,
        ),
      ),
    ),
    home: connected
        ? ConnectedKloterPage(
            invalidConfiguration:
                configurationErrors ?? ReviewApi.invalidConfiguration,
            signIn: signIn,
            homeBuilder: (api, factories, scope, selectFactory, signOut) =>
                _Home(
                  key: ValueKey((api, scope.tenantId, scope.factoryId)),
                  api: api,
                  factories: factories,
                  scope: scope,
                  selectFactory: selectFactory,
                  signOut: signOut,
                ),
          )
        : const _Home(),
  );
}

class _Home extends StatefulWidget {
  const _Home({
    super.key,
    this.api,
    this.factories = const [],
    this.scope,
    this.selectFactory,
    this.signOut,
  });

  final ReviewApi? api;
  final List<FactoryScope> factories;
  final FactoryScope? scope;
  final ValueChanged<FactoryScope>? selectFactory;
  final VoidCallback? signOut;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  NavigatorState get _navigator => Navigator.of(context);
  late final _demo = widget.api == null
      ? DemoProduction()
      : DemoProduction.empty();
  late final _live = widget.api == null
      ? null
      : ConnectedProduction(widget.api!, widget.scope!);
  final _storage = PageStorageBucket();
  final _analytics = DemoAnalytics();
  final _settings = SettingsDemo();
  final _tab = ValueNotifier(NiraTab.beranda);
  final _pages = <NiraTab, Widget>{};

  @override
  void initState() {
    super.initState();
    _live?.refresh();
  }

  List<DemoKloter> get _lots => _live?.lots ?? _demo.kloter;

  String get _role => widget.scope?.role == 'owner' ? 'Pemilik' : 'Admin';
  String _factoryLabel(FactoryScope factory) {
    final count = widget.factories
        .where((other) => other.factoryName == factory.factoryName)
        .length;
    return count > 1
        ? '${factory.factoryName} · ${factory.tenantName}'
        : factory.factoryName;
  }

  void _selectFactory(String id) {
    final factory = widget.factories.firstWhere((item) => item.factoryId == id);
    widget.selectFactory!(factory);
  }

  Widget? _loadStatus() {
    final live = _live;
    if (live == null) return null;
    if (live.loading) return const LinearProgressIndicator();
    final error = live.error;
    if (error == null) return null;
    return _LoadFailed(error, live.refresh);
  }

  Widget _pageFor(NiraTab tab) => _pages.putIfAbsent(
    tab,
    () => ListenableBuilder(
      listenable: _live ?? _demo,
      builder: (context, _) => switch (tab) {
        NiraTab.beranda => BerandaPage(
          kloter: _lots,
          onOpenKloter: _openKloter,
          onQuickAction: _openQuickAction,
          onOpenPekerjaan: _live == null ? null : _openPekerjaan,
          factoryId: widget.scope?.factoryId,
          factories: {
            for (final factory in widget.factories)
              factory.factoryId: _factoryLabel(factory),
          },
          onFactoryChanged: _live == null ? null : _selectFactory,
          profile: _live == null ? null : _role,
          summary: _live == null ? null : _summary(),
          statusMessage:
              _loadStatus() ??
              (_live != null && _lots.isEmpty
                  ? const Text('Belum ada kloter di pabrik ini.')
                  : null),
        ),
        NiraTab.kloter => KloterListPage(
          kloter: _lots,
          onOpenKloter: _openKloter,
          onCreate: widget.scope?.role == 'admin' ? () => _editLot() : null,
          statusMessage: _loadStatus(),
        ),
        NiraTab.laporan => LaporanPage(
          analytics: _analytics,
          onOpenDetail: _openReportDetail,
          approvedLots: _live?.lots,
          loadOfficial: _live == null
              ? null
              : (kind, filter) =>
                    loadFactoryReport(widget.api!, widget.scope!, kind, filter),
          openOfficial: _live == null
              ? null
              : (report) => _openOfficialReport(report.kind, initial: report),
          statusMessage: _loadStatus(),
        ),
        NiraTab.pengaturan => PengaturanPage(
          settings: _settings,
          onNavigate: _navigate,
          connectedProfile: _live == null
              ? null
              : '$_role · ${widget.scope!.factoryName}',
          onConnectedEntry: _live == null
              ? null
              : {
                  SettingSection.operators: () =>
                      _openCatalog(ProductionCatalog.operators),
                },
          catalogLinks: _live == null
              ? const {}
              : {
                  ProductionCatalog.suppliers.label: () =>
                      _openCatalog(ProductionCatalog.suppliers),
                  ProductionCatalog.caneTypes.label: () =>
                      _openCatalog(ProductionCatalog.caneTypes),
                },
          onSignOut: widget.signOut,
        ),
      },
    ),
  );

  ({String cane, String lots}) _summary() {
    final weights = _lots.map((lot) => lot.netWeightKg).nonNulls;
    return (
      cane: formatQuantity(
        weights.isEmpty ? null : weights.reduce((a, b) => a + b),
        'kg',
      ),
      lots: _live!.loading || _live.error != null ? '-' : '${_lots.length}',
    );
  }

  Future<void> _openCatalog(ProductionCatalog kind) async {
    await _navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ProductionCatalogPage(
          api: widget.api!,
          scope: widget.scope!,
          kind: kind,
        ),
      ),
    );
    if (mounted && kind != ProductionCatalog.operators) await _live?.refresh();
  }

  Future<void> _openPekerjaan() async {
    await _navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(widget.scope!.factoryName)),
          body: SafeArea(
            child: PekerjaanPage(
              api: widget.api!,
              factoryId: widget.scope!.factoryId,
              active: true,
            ),
          ),
        ),
      ),
    );
    if (mounted) await _live?.refresh();
  }

  Future<bool> _editLot([Json? lot]) async {
    final saved = await _navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductionLotEditor(
          api: widget.api!,
          scope: widget.scope!,
          lot: lot,
        ),
      ),
    );
    if (mounted && saved == true) await _live?.refresh();
    return saved == true;
  }

  @override
  void dispose() {
    _tab.dispose();
    _demo.dispose();
    _live?.dispose();
    _analytics.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _navigate(NiraTab tab) {
    final navigator = _navigator;
    FocusManager.instance.primaryFocus?.unfocus();
    navigator.popUntil((route) => route.isFirst);
    if (_tab.value == tab) return;
    _tab.value = tab;
  }

  void _openReportDetail(ReportDetailKind kind) {
    _navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailPage(
          kind: kind,
          onNavigate: _navigate,
          row: _analytics.selectedRow,
          analytics: _analytics,
        ),
      ),
    );
  }

  void _openOfficialReport(
    PrintableReportKind kind, {
    PrintableReport? initial,
  }) {
    _navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectedProfitPage(
          api: widget.api!,
          scope: widget.scope!,
          kind: kind,
          onNavigate: _navigate,
          initialFilter: _analytics.dateFilter,
          initialReport: initial,
        ),
      ),
    );
  }

  void _openQuickAction(QuickActionKind action) {
    final kind = switch (action) {
      QuickActionKind.profit => PrintableReportKind.profit,
      QuickActionKind.recap => PrintableReportKind.production,
      _ => null,
    };
    if (kind == null) {
      _navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => action == QuickActionKind.expenses
              ? HargaBiayaPage(
                  settings: _settings,
                  onNavigate: _navigate,
                  operationalFirst: true,
                  unavailable: _live != null,
                )
              : BantuanPage(onNavigate: _navigate),
        ),
      );
      return;
    }
    if (_live != null) {
      _openOfficialReport(kind);
      return;
    }
    _navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _live ?? _demo,
          builder: (_, _) => ReportExportPage(
            kind: kind,
            analytics: _analytics,
            production: _live == null ? _demo : null,
            approvedLots: _live?.lots,
            statusMessage: _loadStatus(),
            factory: widget.scope?.factoryName ?? _settings.factory.name,
            onNavigate: _navigate,
          ),
        ),
      ),
    );
  }

  Future<void> _openKloter(DemoKloter kloter) async {
    final live = _live;
    await _navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => live == null
            ? KloterDetailPage(
                kloter: kloter,
                demo: _demo,
                onNavigate: _navigate,
              )
            : _LotDetail(
                initial: kloter,
                live: live,
                demo: _demo,
                onEdit: _editLot,
                onNavigate: _navigate,
                onOpenPekerjaan: _openPekerjaan,
              ),
      ),
    );
    if (mounted && live != null) await live.refresh();
  }

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _storage,
    child: ValueListenableBuilder<NiraTab>(
      valueListenable: _tab,
      builder: (context, tab, _) => NiraScaffold(
        floatingNavigation: true,
        topGap: tab == NiraTab.laporan ? 4 : 12,
        tab: tab,
        onNavigate: _navigate,
        body: IndexedStack(
          index: tab.index,
          children: [
            for (final destination in NiraTab.values)
              TickerMode(
                enabled: destination == tab,
                child: destination == tab || _pages.containsKey(destination)
                    ? _pageFor(destination)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    ),
  );
}

class _LotDetail extends StatefulWidget {
  const _LotDetail({
    required this.initial,
    required this.live,
    required this.demo,
    required this.onEdit,
    required this.onNavigate,
    required this.onOpenPekerjaan,
  });

  final DemoKloter initial;
  final ConnectedProduction live;
  final DemoProduction demo;
  final Future<bool> Function(Json) onEdit;
  final ValueChanged<NiraTab> onNavigate;
  final VoidCallback onOpenPekerjaan;

  @override
  State<_LotDetail> createState() => _LotDetailState();
}

class _LotDetailState extends State<_LotDetail> {
  ReviewApi get _api => widget.live.api;
  FactoryScope get _scope => widget.live.scope;
  String get _id => widget.initial.id!;
  late DemoKloter _lot = widget.initial;
  late Future<(Json, Json)> _request = _load();

  Future<(Json, Json)> _load() async {
    final results = await Future.wait([
      _api.lot(_scope, _id),
      _api.juice(_scope, _id),
    ]);
    return (results[0], results[1]);
  }

  void _reload() => setState(() => _request = _load());

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(Json, Json)>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        _lot = connectedLot(snapshot.requireData.$1);
      }
      final stock = snapshot.data?.$2;
      return KloterDetailPage(
        kloter: _lot,
        demo: widget.demo,
        onNavigate: widget.onNavigate,
        onOpenPekerjaan: widget.onOpenPekerjaan,
        batchSection: OfficialLotBatches(
          api: _api,
          scope: _scope,
          lotId: _id,
          canCreate:
              _scope.role == 'admin' &&
              _lot.milling.verified &&
              _lot.record?['status'] != 'closed',
          onNavigate: widget.onNavigate,
          onChanged: _reload,
        ),
        onEdit: snapshot.hasError || _scope.role != 'admin'
            ? null
            : () async {
                if (await widget.onEdit(_lot.record!) && mounted) _reload();
              },
        onTransfer: stock == null || snapshot.hasError || _scope.role != 'admin'
            ? null
            : () => _open(
                JuiceTransferPage(api: _api, scope: _scope, lotId: _id),
              ),
        onClosure: snapshot.hasError
            ? null
            : () => _open(LotClosurePage(api: _api, scope: _scope, lotId: _id)),
        stock: switch (snapshot) {
          AsyncSnapshot(connectionState: ConnectionState.waiting) =>
            const LinearProgressIndicator(),
          AsyncSnapshot(:final error?) => _LoadFailed(error, _reload),
          _ => DetailMetrics([
            (
              'Stok fisik nira',
              formatQuantity(_liters(stock?['onHandMl']), 'L'),
            ),
            (
              'Nira direservasi',
              formatQuantity(_liters(stock?['reservedMl']), 'L'),
            ),
            (
              'Nira tersedia',
              formatQuantity(_liters(stock?['availableMl']), 'L'),
            ),
          ]),
        },
      );
    },
  );

  num? _liters(Object? milliliters) {
    final value = num.tryParse(milliliters?.toString() ?? '');
    return value == null ? null : value / 1000;
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed(this.error, this.retry);

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        error is ReviewApiError
            ? (error as ReviewApiError).message
            : 'Data pabrik gagal dimuat.',
      ),
      TextButton(onPressed: retry, child: const Text('Coba lagi')),
    ],
  );
}
