import 'package:flutter/material.dart';

import '../beranda/beranda_page.dart';
import '../bantuan/bantuan_page.dart';
import '../beranda/quick_action_icon.dart';
import '../kloter/connected_production.dart';
import '../kloter/juice_transfer_page.dart';
import '../kloter/lot_closure_page.dart';
import '../kloter/production_catalog_page.dart';
import '../kloter/production_lot_editor.dart';
import '../pekerjaan/pekerjaan_page.dart';
import '../kloter/demo_production.dart';
import '../kloter/demo_lot_fixture.dart';
import '../kloter/kloter_detail_page.dart';
import '../kloter/kloter_detail_widgets.dart';
import '../kloter/kloter_list_page.dart';
import '../laporan/demo_analytics.dart';
import '../laporan/connected_reports.dart';
import '../laporan/connected_batch_detail.dart';
import '../laporan/laporan_page.dart';
import '../laporan/connected_report_view.dart';
import '../laporan/report_detail_page.dart';
import '../laporan/report_export_page.dart';
import '../laporan/printable_report.dart';
import '../pekerjaan/review_api.dart';
import '../pengaturan/pengaturan_page.dart';
import '../pengaturan/settings_demo.dart';
import '../pengaturan/harga_biaya_page.dart';
import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';

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
  State<NiraHome> createState() => _HomeState();
}

class _HomeState extends State<NiraHome> {
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
          period: _live == null
              ? '${_analytics.dateFilter == null ? 'Semua tanggal' : '${formatDate(_analytics.dateFilter!.range.start)} - ${formatDate(_analytics.dateFilter!.range.end)}'} · data sintetis'
              : '${_live.reports.period} · ${_live.reports.synthetic ? 'Data sintetis' : 'Data disahkan'}',
          onPeriod: _live == null
              ? null
              : () => filterConnectedReport(context, _live.reports),
          reportStatus: _live == null
              ? null
              : ConnectedReportStatus(reports: _live.reports),
          statusMessage: _loadStatus(),
        ),
        NiraTab.kloter => KloterListPage(
          kloter: _lots,
          onOpenKloter: _openKloter,
          synthetic: _live?.reports.synthetic ?? false,
          onCreate: _live == null || _live.reports.synthetic
              ? null
              : () => _editLot(),
          statusMessage: _loadStatus(),
        ),
        NiraTab.laporan =>
          _live != null
              ? ConnectedReportView(
                  reports: _live.reports,
                  onNavigate: _navigate,
                )
              : LaporanPage(
                  analytics: _analytics,
                  onOpenDetail: _openReportDetail,
                ),
        NiraTab.pengaturan => PengaturanPage(
          settings: _settings,
          onNavigate: _navigate,
          connectedProfile: _live == null
              ? null
              : '$_role · ${widget.scope!.factoryName}',
          onOpenPekerjaan: _live == null ? null : _openPekerjaan,
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
        cane: live.reports.amount('caneNetKg', unit: ' kg'),
        lots: live.reports.data == null
            ? '—'
            : '${live.reports.totals['lotCount']}',
      );
    }
    return (
      cane: '${demoNumber(_analytics.caneTotal)} kg',
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
          title: const Text('Pekerjaan'),
          onNavigate: _navigate,
          tab: NiraTab.pengaturan,
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
      _navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ConnectedReportExport(
            reports: _live.reports,
            kind: kind,
            onNavigate: _navigate,
          ),
        ),
      );
      return;
    }
    _navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _live == null
              ? _demo
              : Listenable.merge([_live, _live.reports]),
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
  bool get _synthetic => _lot.record?['synthetic'] == true;
  late DemoKloter _lot = widget.initial;
  late Future<(Json, Json, Json, List<Json>?)> _request = _load();

  Future<(Json, Json, Json, List<Json>?)> _load() async {
    var synthetic = _synthetic;
    var lot = await _api.lot(_scope, _id, synthetic: synthetic);
    if (!synthetic && lot['intake'] == null && lot['milling'] == null) {
      final example = await _api.lot(_scope, _id, synthetic: true);
      if (example['intake'] != null || example['milling'] != null) {
        synthetic = true;
        lot = {...example, 'synthetic': true};
      }
    }
    final results = await Future.wait([
      _api.juice(_scope, _id, synthetic: synthetic),
      _api.productionReport(_scope, synthetic: synthetic),
    ]);
    List<Json>? batches;
    try {
      batches = await _api.lotBatches(_scope, _id, synthetic);
    } on ReviewApiError {
      // The approved report remains usable if the batch list is unavailable.
    }
    return (lot, results[0], results[1], batches);
  }

  void _reload() => setState(() => _request = _load());

  String _batchTitle(String code) {
    if (!_synthetic) return code;
    final prefix = '${_lot.code}-B';
    final number = code.startsWith(prefix)
        ? int.tryParse(code.substring(prefix.length))
        : null;
    return number == null ? code : 'Batch $number';
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(Json, Json, Json, List<Json>?)>(
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
            onOpenPekerjaan: _synthetic ? null : widget.onOpenPekerjaan,
            onEdit: _synthetic || !snapshot.hasData || snapshot.hasError
                ? null
                : () async {
                    if (await widget.onEdit(_lot.record!) && mounted) _reload();
                  },
            onTransfer: _synthetic || stock == null || snapshot.hasError
                ? null
                : () => _open(
                    JuiceTransferPage(
                      api: _api,
                      scope: _scope,
                      lotId: _id,
                      onNavigate: widget.onNavigate,
                    ),
                  ),
            onClosure: _synthetic || !snapshot.hasData || snapshot.hasError
                ? null
                : () => _open(
                    LotClosurePage(
                      api: _api,
                      scope: _scope,
                      lotId: _id,
                      onNavigate: widget.onNavigate,
                    ),
                  ),
            production: snapshot.hasData
                ? _production(snapshot.requireData.$3, snapshot.requireData.$4)
                : Text(
                    snapshot.hasError
                        ? 'Batch gagal dimuat.'
                        : 'Memuat batch sah…',
                  ),
            stock: switch (snapshot) {
              AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                const LinearProgressIndicator(),
              AsyncSnapshot(:final error?) => _LoadFailed(error, _reload),
              _ when _synthetic => null,
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

  Widget _production(Json report, List<Json>? records) {
    final lots = (report['items'] as List).cast<Json>().where(
      (lot) => lot['lotId'] == _id,
    );
    final lot = lots.firstOrNull;
    final approved = {
      for (final row in (lot?['batches'] as List? ?? []).cast<Json>())
        row['code']: row,
    };
    final batches = records == null || records.isEmpty
        ? approved.values.toList()
        : records;
    bool needsReview(Json row) =>
        row.containsKey('status') && row['status'] != 'approved';
    final pending = batches.where(needsReview).length;
    void open([Json? batch]) => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectedReportDetail(
          data: report,
          lot: lot!,
          batch: batch,
          navigationTab: NiraTab.kloter,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
    void openBatch(Json batch) {
      if (approved[batch['code']] case final official?) {
        open(official);
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ConnectedBatchDetail(
            batch: {
              'code': batch['code'],
              'physicalWeightKg': batch['physical_weight_kg'],
              'quantityMl': batch['quantity_ml'],
              'wokNumber': batch['wok_number'],
              'occurredAt': batch['occurred_at'],
            },
            lotCode: _lot.code,
            source: _synthetic ? 'Data sintetis' : 'Data produksi',
            reviewed: !needsReview(batch),
            hasReport: false,
            marginDetails: const [],
            onNavigate: widget.onNavigate,
            navigationTab: NiraTab.kloter,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (batches.isEmpty)
          Text(
            lot == null ? 'Belum ada penerimaan sah.' : 'Belum ada batch sah.',
          ),
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: NiraSpace.sm),
            child: Text(
              '$pending Batch perlu ditinjau',
              style: niraText(NiraType.caption, color: niraOchre),
            ),
          ),
        if (records == null && approved.isNotEmpty)
          const Text('Daftar batch lengkap gagal dimuat.'),
        for (final batch in batches)
          Padding(
            padding: const EdgeInsets.only(bottom: NiraSpace.md),
            child: KloterBatchTile(
              title: _batchTitle(batch['code'] as String),
              juice: formatQuantity(
                _liters(batch['quantity_ml'] ?? batch['quantityMl']),
                'L',
              ),
              physicalWeight:
                  '${reportNumber(batch['physical_weight_kg'] ?? batch['physicalWeightKg'])} kg',
              pending: needsReview(batch),
              onTap: () => openBatch(batch),
            ),
          ),
        if (lot != null)
          TextButton(
            onPressed: () => open(),
            child: const Text('Produksi dan margin kloter'),
          ),
      ],
    );
  }

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
