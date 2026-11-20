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
    super.key,
  });

  final ConnectedProduction production;
  final ValueChanged<NiraTab> onNavigate;

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
    _pager.refresh();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<Json> _load() async {
    final report = await _production.api.productionReport(
      _production.scope,
      synthetic: _synthetic,
    );
    if (report['items'] is! List) {
      throw const FormatException('Rincian kloter tidak tersedia.');
    }
    return report;
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_production, _pager]),
    builder: (context, _) => FutureBuilder<Json>(
      future: _report,
      builder: (context, snapshot) => _expenses(snapshot),
    ),
  );

  Widget _expenses(AsyncSnapshot<Json> snapshot) {
    final lots = (snapshot.data?['items'] as List? ?? const []).cast<Json>();
    final approved = {
      for (final lot in lots)
        if (lot['calculation'] != null) lot['lotId'] as String: lot,
    };
    final editable = [
      if (!_synthetic && _production.scope.role == 'admin')
        for (final lot in _pager.items)
          if (lot.id != null &&
              lot.intake.verified &&
              lot.status != KloterStatus.done &&
              !approved.containsKey(lot.id))
            lot,
    ];
    return SettingsPageFrame(
      title: 'Biaya Operasional',
      tab: NiraTab.beranda,
      onNavigate: widget.onNavigate,
      subtitle: _synthetic
          ? 'Harga dan biaya per kloter · Data sintetis'
          : 'Harga dan biaya per kloter',
      children: [
        if (snapshot.connectionState != ConnectionState.done)
          const NiraLoading(label: 'Memuat biaya…')
        else if (snapshot.hasError) ...[
          const SettingsNote('Data harga dan biaya belum bisa dimuat.'),
          TextButton(
            onPressed: () => setState(() => _report = _load()),
            child: const Text('Coba lagi'),
          ),
        ] else ...[
          if (editable.isEmpty &&
              approved.isEmpty &&
              !_pager.loading &&
              _pager.error == null &&
              !_pager.hasMore)
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
          for (final lot in approved.values) _approvedCosts(lot),
          if (!_synthetic && _production.scope.role == 'admin') ...[
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
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(lot['code'] as String),
      subtitle: Text(lot['supplier'] as String),
      children: [
        for (final (key, label) in const [
          ('operationalRupiah', 'Biaya operasional'),
          ('caneRupiah', 'Biaya tebu'),
          ('ingredientRupiah', 'Biaya bahan'),
          ('otherRupiah', 'Biaya lain'),
        ])
          ListTile(title: Text(label), subtitle: Text(_costValue(costs?[key]))),
        for (final (code, price) in prices)
          ListTile(
            title: Text('Grade $code'),
            subtitle: Text('${reportMoney(price)}/kg'),
          ),
      ],
    );
  }
}
