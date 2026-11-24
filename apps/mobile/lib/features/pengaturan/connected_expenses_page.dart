import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../kloter/connected_production.dart';
import '../kloter/connected_lot_pager.dart';
import '../kloter/lot_page_footer.dart';
import '../kloter/demo_production.dart';
import '../kloter/official_batch_workflow.dart';
import '../laporan/connected_reports.dart';
import '../pekerjaan/review_api.dart';
import 'settings_widgets.dart';

class ConnectedExpensesPage extends StatefulWidget {
  const ConnectedExpensesPage({
    required this.production,
    required this.onNavigate,
    this.fromSettings = false,
    super.key,
  });

  final ConnectedProduction production;
  final ValueChanged<NiraTab> onNavigate;
  final bool fromSettings;

  @override
  State<ConnectedExpensesPage> createState() => _ConnectedExpensesPageState();
}

class _ConnectedExpensesPageState extends State<ConnectedExpensesPage> {
  ConnectedProduction get _production => widget.production;
  late final bool _synthetic = _production.reports.synthetic;
  late final _pager = ConnectedLotPager(
    _production.api,
    _production.scope,
    synthetic: _synthetic,
    status: 'open',
  );
  late Future<Json> _report = _load();
  final _saved = <String, Json>{};

  @override
  void initState() {
    super.initState();
    if (!widget.fromSettings &&
        !_synthetic &&
        _production.scope.role == 'admin') {
      _pager.refresh();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<Json> _load() async {
    if (widget.fromSettings) {
      final factory = await _production.api.getProduction(
        _production.scope.basePath,
      );
      if (factory['role'] != 'owner') throw const ReviewApiError(403);
    }
    final report = await _production.api.productionReport(
      _production.scope,
      synthetic: _synthetic,
    );
    if (report['items'] case final List items
        when items.every(
          (item) =>
              item is Json &&
              item['lotId'] is String &&
              item['code'] is String &&
              item['supplier'] is String &&
              (item['calculation'] == null || item['calculation'] is Json),
        )) {
      return report;
    } else {
      throw const FormatException('Rincian kloter tidak tersedia.');
    }
  }

  Future<void> _save(DemoKloter lot) async {
    final result = await showLotCostsForm(
      context,
      _production.api,
      _production.scope,
      lot.id!,
      lot.code,
    );
    if (!mounted || result == null) return;
    setState(() => _saved[lot.id!] = result);
    _production.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fromSettings && _production.scope.role != 'owner') {
      return SettingsPageFrame(
        title: 'Harga & Biaya',
        subtitle: _production.scope.factoryName,
        keepTitleVisible: true,
        onNavigate: widget.onNavigate,
        children: const [
          SettingsMessage(
            icon: Icons.lock_outline,
            message:
                'Rincian harga dan biaya di Pengaturan tersedia untuk pemilik pabrik.',
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_production, _pager]),
      builder: (context, _) => FutureBuilder<Json>(
        future: _report,
        builder: (context, snapshot) => _expenses(snapshot),
      ),
    );
  }

  Widget _expenses(AsyncSnapshot<Json> snapshot) {
    final lots = (snapshot.data?['items'] as List? ?? const []).cast<Json>();
    final approved = {
      for (final lot in lots)
        if (lot['calculation'] != null) lot['lotId'] as String: lot,
    };
    final editable = [
      if (!widget.fromSettings &&
          !_synthetic &&
          _production.scope.role == 'admin')
        for (final lot in _pager.items)
          if (lot.id != null &&
              lot.intake.verified &&
              lot.status != KloterStatus.done &&
              !approved.containsKey(lot.id))
            lot,
    ];
    return SettingsPageFrame(
      title: widget.fromSettings ? 'Harga & Biaya' : 'Biaya Operasional',
      keepTitleVisible: widget.fromSettings,
      tab: widget.fromSettings ? NiraTab.pengaturan : NiraTab.beranda,
      onNavigate: widget.onNavigate,
      subtitle: [
        if (widget.fromSettings) _production.scope.factoryName,
        if (widget.fromSettings)
          'Semua tanggal'
        else
          'Harga dan biaya per kloter',
        if (_synthetic) 'Data sintetis',
      ].join(' · '),
      children: [
        if (snapshot.connectionState != ConnectionState.done)
          const NiraLoading(label: 'Memuat biaya…')
        else if (snapshot.hasError)
          SettingsLoadError(
            accessDenied: switch (snapshot.error) {
              ReviewApiError(status: 403) => true,
              _ => false,
            },
            message: 'Data harga dan biaya belum bisa dimuat.',
            onRetry: () => setState(() {
              _report = _load();
            }),
          )
        else ...[
          if (widget.fromSettings) ...[
            const SettingsMessage(
              icon: Icons.receipt_long_outlined,
              title: 'Rincian per kloter',
              message:
                  'Buka kloter untuk melihat rincian harga jual dan biaya dari produksi yang sudah disahkan.',
            ),
            const SizedBox(height: NiraSpace.md),
          ],
          if (editable.isEmpty &&
              approved.isEmpty &&
              (widget.fromSettings ||
                  (!_pager.loading && _pager.error == null && !_pager.hasMore)))
            if (widget.fromSettings)
              const SettingsMessage(
                icon: Icons.inbox_outlined,
                message: 'Belum ada biaya operasional tercatat.',
              )
            else
              const SettingsNote('Belum ada biaya operasional tercatat.'),
          if (editable.isNotEmpty) ...[
            const SettingsNote(
              'Empat komponen biaya tersimpan bersama dan dapat diperbarui sebelum batch pertama divalidasi.',
            ),
            for (final lot in editable)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(lot.code),
                subtitle: Text(
                  _saved.containsKey(lot.id)
                      ? _costValue(_saved[lot.id]?['operational_rupiah'])
                      : lot.supplier,
                ),
                trailing: _saved.containsKey(lot.id)
                    ? const Tooltip(
                        message: 'Biaya tersimpan',
                        child: Icon(
                          Icons.check_circle_outline,
                          color: niraGreen,
                        ),
                      )
                    : TextButton(
                        onPressed: () => _save(lot),
                        child: const Text('Isi biaya'),
                      ),
              ),
          ],
          for (final lot in approved.values)
            if (widget.fromSettings)
              Padding(
                padding: const EdgeInsets.only(bottom: NiraSpace.md),
                child: SettingsPanel(
                  padding: EdgeInsets.zero,
                  child: _approvedCosts(lot),
                ),
              )
            else
              _approvedCosts(lot),
          if (!widget.fromSettings &&
              !_synthetic &&
              _production.scope.role == 'admin') ...[
            if (_pager.loading) const NiraLoading(label: 'Memuat kloter…'),
            if (_pager.error != null)
              TextButton(
                onPressed: _pager.refresh,
                child: const Text('Coba lagi kloter untuk biaya'),
              ),
            LotPageFooter(_pager),
          ],
        ],
      ],
    );
  }

  String _costValue(Object? cost) => cost == null ? '—' : reportMoney(cost);

  Widget _approvedCosts(Json lot) {
    final calculation = lot['calculation'] as Json;
    final costs = calculation['costs'] as Json?;
    final prices = <(String, String)>{
      for (final batch in (lot['batches'] as List? ?? const []).cast<Json>())
        for (final grade in (batch['grades'] as List? ?? const []).cast<Json>())
          if (grade['code'] case final String code)
            if (grade['pricePerKgRupiah'] case final String price)
              (code, price),
    };
    if (widget.fromSettings) {
      return ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: NiraSpace.lg),
        childrenPadding: const EdgeInsets.fromLTRB(
          NiraSpace.lg,
          NiraSpace.xs,
          NiraSpace.lg,
          NiraSpace.lg,
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: niraGreen,
        collapsedIconColor: niraGreen,
        title: Text(
          lot['code'] as String,
          style: niraText(NiraType.section, weight: FontWeight.w700),
        ),
        subtitle: Text(
          lot['supplier'] as String,
          style: niraText(NiraType.body, color: niraLeaf),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: NiraSpace.lg, color: niraLine),
          _heading('Komponen biaya'),
          for (final (key, label) in _costFields)
            _amountRow(label, _costValue(costs?[key])),
          if (prices.isNotEmpty) ...[
            const Divider(height: NiraSpace.xl, color: niraLine),
            _heading('Harga jual per grade'),
            for (final (code, price) in prices)
              _amountRow('Grade $code', '${reportMoney(price)}/kg'),
          ],
        ],
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(lot['code'] as String),
      subtitle: Text(lot['supplier'] as String),
      children: [
        for (final (key, label) in _costFields)
          ListTile(title: Text(label), subtitle: Text(_costValue(costs?[key]))),
        for (final (code, price) in prices)
          ListTile(
            title: Text('Grade $code'),
            subtitle: Text('${reportMoney(price)}/kg'),
          ),
      ],
    );
  }

  static const _costFields = [
    ('operationalRupiah', 'Biaya operasional'),
    ('caneRupiah', 'Biaya tebu'),
    ('ingredientRupiah', 'Biaya bahan'),
    ('otherRupiah', 'Biaya lain'),
  ];

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: NiraSpace.xs),
    child: Text(title, style: niraText(NiraType.body, weight: FontWeight.w700)),
  );

  Widget _amountRow(String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: niraText(NiraType.body, color: niraLeaf)),
        ),
        const SizedBox(width: NiraSpace.md),
        Expanded(
          child: Text(
            amount,
            textAlign: TextAlign.end,
            style: niraText(NiraType.body, weight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
