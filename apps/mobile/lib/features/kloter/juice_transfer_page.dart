import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../pekerjaan/review_api.dart';
import '../pekerjaan/production_api.dart';
import 'juice_volume.dart';

class JuiceTransferPage extends StatefulWidget {
  const JuiceTransferPage({
    super.key,
    required this.api,
    required this.scope,
    required this.lotId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String lotId;

  @override
  State<JuiceTransferPage> createState() => _JuiceTransferPageState();
}

class _JuiceTransferPageState extends State<JuiceTransferPage> {
  final _form = GlobalKey<FormState>();
  final _liters = TextEditingController();
  Json? _destination;
  String? _originId;
  bool _working = false;
  String? _error;
  Json? _receipt;
  JuiceTransferRequest? _completed;
  late Future<List<Json>> _data = _load();
  JuiceTransferRequest? get _pending =>
      widget.api.pendingTransfer(widget.scope, widget.lotId);

  Future<List<Json>> _load() {
    final request =
        Future.wait([
          widget.api.lot(widget.scope, widget.lotId),
          widget.api.juice(widget.scope, widget.lotId),
        ]).then((data) async {
          final [lot, stock] = data;
          final origins = (stock['origins'] as List).cast<Json>().where(
            (origin) =>
                origin['originLotId'] != widget.lotId &&
                compareJuiceVolumes(origin['availableMl'] as String, '0') > 0,
          );
          final sources = await Future.wait(
            origins.map(
              (origin) =>
                  widget.api.lot(widget.scope, origin['originLotId'] as String),
            ),
          );
          return [
            lot,
            stock,
            <String, dynamic>{
              for (final source in sources)
                source['id'] as String: source['displayCode'] ?? source['id'],
            },
          ];
        });
    request.ignore();
    return request;
  }

  @override
  void dispose() {
    _liters.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _chooseDestination() async {
    final destination = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        builder: (_) => _TransferDestination(
          api: widget.api,
          scope: widget.scope,
          sourceId: widget.lotId,
        ),
      ),
    );
    if (mounted && destination != null) {
      setState(() => _destination = destination);
    }
  }

  Future<void> _submit(Json origin, Json labels) async {
    if (_working || !_form.currentState!.validate()) return;
    if (_destination == null) {
      setState(() => _error = 'Pilih kloter tujuan.');
      return;
    }
    final request = widget.api.prepareTransfer(
      widget.scope,
      widget.lotId,
      toLotId: _destination!['id'] as String,
      toLabel: '${_destination!['displayCode'] ?? _destination!['id']}',
      originLotId: origin['originLotId'] as String,
      originLabel: origin['originLotId'] == widget.lotId
          ? 'Nira kloter ini'
          : 'Nira asal ${labels[origin['originLotId']] ?? origin['originLotId']}',
      quantityMl: litersToMilliliters(_liters.text)!,
    );
    await _send(request);
  }

  Future<void> _send(JuiceTransferRequest request) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final receipt = await JuiceApi(widget.api).transfer(
        widget.scope,
        widget.lotId,
        request,
      );
      if (mounted) {
        setState(() {
          _receipt = receipt;
          _completed = request;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            ReviewApiError(status: 409) =>
              'Transfer ditolak. Muat ulang saldo dan periksa status kedua kloter sebelum mencoba lagi.',
            ReviewApiError(status: 400) =>
              'Periksa tujuan dan volume transfer.',
            ReviewApiError(status: 401) =>
              'Sesi masuk berakhir. Simpan ID permintaan untuk pemeriksaan transfer.',
            ReviewApiError(status: 403) || ReviewApiError(status: 404) =>
              'Kloter atau akses pabrik tidak tersedia. Simpan ID permintaan untuk pemeriksaan transfer.',
            _ =>
              'Hasil transfer belum terkonfirmasi. Coba lagi permintaan yang sama untuk memeriksa hasilnya.',
          };
          _data = _load();
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _summary(JuiceTransferRequest request) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        title: const Text('Kloter tujuan'),
        subtitle: Text(request.toLabel),
      ),
      ListTile(
        title: const Text('Asal nira'),
        subtitle: Text(request.originLabel),
      ),
      ListTile(
        title: const Text('Volume transfer'),
        subtitle: Text('${millilitersToLiters(request.quantityMl)} L'),
      ),
      ListTile(
        title: const Text('ID permintaan'),
        subtitle: SelectableText(request.requestId),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Transfer nira'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang saldo',
            onPressed: _working ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.scope.factoryName),
            if (_working) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_receipt != null) ...[
              Text(
                'Transfer tercatat',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _summary(_completed!),
              ListTile(
                title: const Text('Dicatat oleh'),
                subtitle: SelectableText('${_receipt!['createdBy']}'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kembali ke detail'),
              ),
            ] else if (_pending case final JuiceTransferRequest request) ...[
              const Text('Permintaan transfer menunggu konfirmasi hasil.'),
              _summary(request),
              FilledButton(
                onPressed: _working ? null : () => _send(request),
                child: const Text('Coba lagi transfer yang sama'),
              ),
            ] else
              FutureBuilder<List<Json>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    return Column(
                      children: [
                        Text(
                          error is ReviewApiError
                              ? error.message
                              : 'Saldo nira gagal dimuat.',
                        ),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    );
                  }
                  final [lot, stock, labels] = snapshot.requireData;
                  if (lot['status'] == 'closed') {
                    return const Text(
                      'Kloter ditutup. Buka kembali kloter untuk melakukan transfer.',
                    );
                  }
                  final origins = (stock['origins'] as List)
                      .cast<Json>()
                      .where(
                        (origin) =>
                            compareJuiceVolumes(
                              origin['availableMl'] as String,
                              '0',
                            ) >
                            0,
                      )
                      .toList();
                  if (origins.isEmpty) {
                    return const Text(
                      'Belum ada nira tersedia untuk ditransfer.',
                    );
                  }
                  final selectedId =
                      origins.any(
                        (origin) => origin['originLotId'] == _originId,
                      )
                      ? _originId
                      : origins.first['originLotId'] as String;
                  final selected = origins.firstWhere(
                    (origin) => origin['originLotId'] == selectedId,
                  );
                  return Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: const Text('Kloter pemegang stok'),
                          subtitle: Text('${lot['displayCode'] ?? lot['id']}'),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedId),
                          initialValue: selectedId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Asal nira',
                          ),
                          items: [
                            for (final origin in origins)
                              DropdownMenuItem(
                                value: origin['originLotId'] as String,
                                child: Text(
                                  origin['originLotId'] == widget.lotId
                                      ? 'Nira kloter ini'
                                      : 'Asal ${labels[origin['originLotId']] ?? origin['originLotId']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _working
                              ? null
                              : (value) => setState(() => _originId = value),
                        ),
                        ListTile(
                          title: const Text('Nira tersedia dari sumber ini'),
                          subtitle: Text(
                            '${millilitersToLiters(selected['availableMl'] as String)} L',
                          ),
                        ),
                        ListTile(
                          title: const Text('Kloter tujuan'),
                          subtitle: Text(
                            _destination == null
                                ? 'Pilih kloter dalam pabrik ini'
                                : '${_destination!['displayCode'] ?? _destination!['id']}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _working ? null : _chooseDestination,
                        ),
                        TextFormField(
                          controller: _liters,
                          enabled: !_working,
                          maxLength: 64,
                          decoration: const InputDecoration(
                            labelText: 'Volume transfer (L)',
                            helperText:
                                'Gunakan koma atau titik desimal, tanpa pemisah ribuan.',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final ml = litersToMilliliters(value!);
                            if (ml == null) {
                              return 'Isi volume positif dalam liter.';
                            }
                            return compareJuiceVolumes(
                                      ml,
                                      selected['availableMl'] as String,
                                    ) >
                                    0
                                ? 'Volume melebihi nira tersedia dari sumber ini.'
                                : null;
                          },
                        ),
                        FilledButton(
                          onPressed: _working
                              ? null
                              : () => _submit(selected, labels),
                          child: const Text('Kirim transfer'),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _TransferDestination extends StatefulWidget {
  const _TransferDestination({
    required this.api,
    required this.scope,
    required this.sourceId,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final String sourceId;
  @override
  State<_TransferDestination> createState() => _TransferDestinationState();
}

class _TransferDestinationState extends State<_TransferDestination> {
  final _pageHeight = NiraPageHeight();
  final _search = TextEditingController();
  String _query = '';
  int _offset = 0;
  late Future<Json> _page = _load();

  Future<Json> _load() {
    final request = widget.api.lots(
      widget.scope,
      offset: _offset,
      search: _query,
    );
    request.ignore();
    return request;
  }

  void _reload() => setState(() {
    _page = _load();
  });
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pilih kloter tujuan')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.scope.factoryName),
          TextField(
            controller: _search,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Cari kode kloter atau pemasok',
              suffixIcon: IconButton(
                tooltip: 'Cari kloter tujuan',
                icon: const Icon(Icons.search),
                onPressed: () {
                  _query = _search.text.trim();
                  _offset = 0;
                  _reload();
                },
              ),
            ),
            onSubmitted: (value) {
              _query = value.trim();
              _offset = 0;
              _reload();
            },
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
                          : 'Kloter tujuan gagal dimuat.',
                    ),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                );
              }
              final page = snapshot.requireData;
              final rows = (page['items'] as List)
                  .cast<Json>()
                  .where((lot) => lot['id'] != widget.sourceId)
                  .toList();
              final limit = page['limit'] as int;
              final total = page['total'] as int;
              return Column(
                children: [
                  NiraPageBody(
                    height: _pageHeight,
                    firstPage: _offset == 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (rows.isEmpty)
                          const ListTile(
                            title: Text('Tidak ada kloter tujuan pada halaman ini.'),
                          ),
                        for (final lot in rows)
                          ListTile(
                            title: Text('${lot['displayCode'] ?? lot['id']}'),
                            subtitle: Text('${lot['supplierName']}'),
                            onTap: () => Navigator.pop(context, lot),
                          ),
                      ],
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
        ],
      ),
    ),
  );
}
