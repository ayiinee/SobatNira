import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../beranda/beranda_page.dart';
import '../bantuan/bantuan_page.dart';
import '../beranda/quick_action_icon.dart';
import '../kloter/connected_production.dart';
import '../kloter/official_batch_workflow.dart';
import '../kloter/juice_transfer_page.dart';
import '../kloter/lot_closure_page.dart';
import '../kloter/production_catalog_page.dart';
import '../kloter/production_lot_editor.dart';
import '../pekerjaan/pekerjaan_page.dart';
import '../kloter/demo_production.dart';
import '../kloter/demo_lot_fixture.dart';
import '../kloter/kloter_detail_page.dart';
import '../kloter/kloter_list_page.dart';
import '../laporan/demo_analytics.dart';
import '../laporan/laporan_page.dart';
import '../laporan/connected_report_controls.dart';
import '../laporan/report_detail_page.dart';
import '../laporan/report_export_page.dart';
import '../laporan/printable_report.dart';
import '../pekerjaan/review_api.dart';
import '../pengaturan/pengaturan_page.dart';
import '../pengaturan/settings_demo.dart';
import '../pengaturan/harga_biaya_page.dart';
import '../pengaturan/connected_expenses_page.dart';
import '../../sobatnira_ui.dart';

import '../../widgets/page_frame.dart';

const _localMode = String.fromEnvironment('SOBATNIRA_MODE') == 'local';

class NiraHome extends StatefulWidget {
  const NiraHome({
    super.key,
    this.api,
    this.factories = const [],
    this.scope,
    this.selectFactory,
    this.signOut,
    this.synthetic = false,
    this.onSyntheticChanged,
  });

  final ReviewApi? api;
  final List<FactoryScope> factories;
  final FactoryScope? scope;
  final ValueChanged<FactoryScope>? selectFactory;
  final VoidCallback? signOut;
  final bool synthetic;
  final ValueChanged<bool>? onSyntheticChanged;

  @override
  State<NiraHome> createState() => _NiraHomeState();
}

class _NiraHomeState extends State<NiraHome> {
  NavigatorState get _navigator => Navigator.of(context);
  late final _demo = widget.api == null
      ? DemoProduction()
      : DemoProduction.empty();
  late final _live = widget.api == null
      ? null
      : ConnectedProduction(
          widget.api!,
          widget.scope!,
          synthetic: widget.synthetic,
          onSyntheticChanged: widget.onSyntheticChanged,
        );
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
  bool get _allowSessionSettings =>
      _live == null || (_localMode && widget.scope?.role == 'admin');

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
    if (live.loading) return const NiraLoading(label: 'Memuat kloter…');
    final error = live.error;
    if (error == null) return null;
    return _LoadFailed(error, live.refresh);
  }

  Widget _pageFor(NiraTab tab) => _pages.putIfAbsent(
    tab,
    () => ListenableBuilder(
      listenable: _live == null
          ? Listenable.merge([_demo, _analytics])
          : Listenable.merge([_live, _live.reports]),
      builder: (context, _) => switch (tab) {
        NiraTab.beranda => BerandaPage(
          kloter: _lots,
          onOpenKloter: _openKloter,
          onQuickAction: _openQuickAction,
          factoryId: widget.scope?.factoryId,
          factories: {
            for (final factory in widget.factories)
              factory.factoryId: _factoryLabel(factory),
          },
          onFactoryChanged: _live == null ? null : _selectFactory,
          profile: _live == null ? null : _role,
          summary: _summary(),
          profit:
              _live?.reports.amount('productionMarginRupiah', money: true) ??
              demoMoney(_analytics.marginTotal),
          reportStatus: _live == null || _live.loading
              ? null
              : ConnectedReportStatus(reports: _live.reports, compact: true),
          statusMessage:
              _loadStatus() ??
              (_live != null && _lots.isEmpty
                  ? const Text('Belum ada kloter di pabrik ini.')
                  : null),
        ),
        NiraTab.kloter => KloterListPage(
          kloter: _lots,
          onOpenKloter: _openKloter,
          filterToday: _live?.reports.filterToday,
          onCreate:
              widget.scope?.role == 'admin' &&
                  !(_live?.reports.synthetic ?? false)
              ? () => _editLot()
              : null,
          statusMessage: _loadStatus(),
        ),
        NiraTab.laporan => LaporanPage(
          analytics: _analytics,
          reports: _live?.reports,
          onOpenDetail: _openReportDetail,
        ),
        NiraTab.pengaturan => PengaturanPage(
          settings: _settings,
          onNavigate: _navigate,
          allowSessionSettings: _allowSessionSettings,
          onOpenPekerjaan: _live == null ? null : _openPekerjaan,
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
    final live = _live;
    if (live != null) {
      return (
        cane: live.reports.amount('caneNetKg'),
        lots: live.reports.data == null
            ? '—'
            : '${live.reports.totals['lotCount']}',
      );
    }
    return (
      cane: demoNumber(_analytics.caneTotal),
      lots: '${_analytics.visibleLots.length}',
    );
  }

  Future<void> _openCatalog(ProductionCatalog kind) async {
    await _navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ProductionCatalogPage(
          api: widget.api!,
          scope: widget.scope!,
          kind: kind,
          onNavigate: _navigate,
        ),
      ),
    );
    if (mounted && kind != ProductionCatalog.operators) await _live?.refresh();
  }

  Future<void> _openPekerjaan() async {
    await _navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => NiraPageScaffold(
          title: Text(widget.scope!.factoryName),
          tab: NiraTab.pengaturan,
          onNavigate: _navigate,
          body: SafeArea(
            child: PekerjaanPage(
              api: widget.api!,
              factoryId: widget.scope!.factoryId,
              active: true,
              onNavigate: _navigate,
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
          onNavigate: _navigate,
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
    final row = _analytics.selectedRow;
    final reports = _live?.reports;
    final report = reports?.data;
    final lot = reports?.lots
        .where((item) => item['lotId'] == row?.id)
        .firstOrNull;
    if (reports != null && report == null) return;
    _navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailPage(
          kind: kind,
          onNavigate: _navigate,
          row: row,
          analytics: _analytics,
          report: report,
          officialLot: lot,
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
          builder: (_) {
            if (action != QuickActionKind.expenses) {
              return BantuanPage(onNavigate: _navigate);
            }
            if (_live case final live?) {
              return ConnectedExpensesPage(
                production: live,
                onNavigate: _navigate,
              );
            }
            return HargaBiayaPage(
              settings: _settings,
              onNavigate: _navigate,
              operationalFirst: true,
            );
          },
        ),
      );
      return;
    }
    _navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ReportExportPage(
          kind: kind,
          analytics: _analytics,
          production: _live == null ? _demo : null,
          reports: _live?.reports,
          factory: widget.scope?.factoryName ?? _settings.factory.name,
          onNavigate: _navigate,
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
  late Future<Json> _request = _load();

  bool get _synthetic => widget.live.reports.synthetic;

  Future<Json> _load() => _api.lot(_scope, _id, synthetic: _synthetic);

  void _reload() {
    final request = _load();
    setState(() {
      _request = request;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        _lot = connectedLot(snapshot.requireData);
      }
      final canManage =
          snapshot.hasData && _scope.role == 'admin' && !_synthetic;
      return KloterDetailPage(
        kloter: _lot,
        demo: widget.demo,
        onNavigate: widget.onNavigate,
        onOpenPekerjaan: widget.onOpenPekerjaan,
        approvedPhoto: (revision) => _api.approvedPhoto(_scope, revision),
        onReturnFromProcess: () {
          if (mounted) _reload();
        },
        onEdit: canManage ? () => widget.onEdit(_lot.record!) : null,
        onTransfer: canManage
            ? () => _open(
                JuiceTransferPage(
                  api: _api,
                  scope: _scope,
                  lotId: _id,
                  onNavigate: widget.onNavigate,
                ),
              )
            : null,
        onClosure: snapshot.hasError || _synthetic
            ? null
            : () => _open(
                LotClosurePage(
                  api: _api,
                  scope: _scope,
                  lotId: _id,
                  onNavigate: widget.onNavigate,
                ),
              ),
        production: OfficialLotBatches(
          api: _api,
          scope: _scope,
          lotId: _id,
          synthetic: _synthetic,
          kloterCode: _lot.code,
          caneWeight: _lot.weight,
          kloter: _lot,
          onOpenPekerjaan: widget.onOpenPekerjaan,
          millingRevision: _lot.noteRevision(intake: false),
          canCreate:
              _scope.role == 'admin' &&
              !_synthetic &&
              _lot.milling.verified &&
              _lot.record?['status'] != 'closed',
          onNavigate: widget.onNavigate,
          onChanged: () {
            _reload();
            widget.live.reports.refresh();
          },
          reportLink: _production,
        ),
        loadStock: () => _api.juice(_scope, _id, synthetic: _synthetic),
        statusMessage: snapshot.hasError
            ? _LoadFailed(snapshot.error!, _reload)
            : null,
      );
    },
  );

  Future<void> _production([String? batchId]) async {
    final notice = ScaffoldMessenger.of(context);
    try {
      final report = await _api.productionReport(_scope, synthetic: _synthetic);
      if (!mounted) return;
      final lot = (report['items'] as List)
          .cast<Json>()
          .where((item) => item['lotId'] == _id)
          .firstOrNull;
      if (lot == null) {
        notice.showSnackBar(
          const SnackBar(content: Text('Belum ada penerimaan sah.')),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportDetailPage(
            kind: ReportDetailKind.margin,
            report: report,
            officialLot: lot,
            batchId: batchId,
            onNavigate: widget.onNavigate,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        notice.showSnackBar(
          const SnackBar(
            content: Text('Laporan belum dapat dimuat. Coba lagi.'),
          ),
        );
      }
    }
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
