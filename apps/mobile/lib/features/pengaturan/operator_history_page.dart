import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import '../pekerjaan/review_api.dart';

class OperatorHistoryPage extends StatefulWidget {
  const OperatorHistoryPage({
    super.key,
    required this.api,
    required this.scope,
    required this.operatorId,
    required this.phone,
    this.onNavigate,
  });

  final ValueChanged<NiraTab>? onNavigate;
  final ReviewApi api;
  final FactoryScope scope;
  final String operatorId;
  final String phone;

  @override
  State<OperatorHistoryPage> createState() => _OperatorHistoryPageState();
}

class _OperatorHistoryPageState extends State<OperatorHistoryPage> {
  final _pageHeight = NiraPageHeight();
  int _offset = 0;
  late Future<Json> _page = _fetch();

  Future<Json> _fetch() => widget.api.operatorHistory(
    widget.scope,
    widget.operatorId,
    offset: _offset,
  );

  void _load(int offset) => setState(() {
    _offset = offset;
    _page = _fetch();
  });

  @override
  Widget build(BuildContext context) => NiraPageScaffold(
    onNavigate: widget.onNavigate,
    tab: NiraTab.pengaturan,
    title: const Text('Riwayat operator'),
    actions: [
      IconButton(
        tooltip: 'Muat ulang riwayat',
        onPressed: () => _load(_offset),
        icon: const Icon(Icons.refresh),
      ),
    ],
    body: SafeArea(
      child: NiraPagedFutureBuilder<Json>(
        future: _page,
        page: _offset,
        dataset: (widget.scope.factoryId, widget.operatorId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error is ReviewApiError
                        ? error.message
                        : 'Riwayat operator gagal dimuat.',
                  ),
                  TextButton(
                    onPressed: () => _load(_offset),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            );
          }
          final page = snapshot.requireData;
          final entries = (page['items'] as List).cast<Json>();
          final limit = page['limit'] as int;
          final total = page['total'] as int;
          final hasNext = _offset + limit < total;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.scope.factoryName),
              Text(widget.phone),
              NiraPageBody(
                height: _pageHeight,
                firstPage: _offset == 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (entries.isEmpty)
                      const ListTile(
                        title: Text('Belum ada riwayat operator.'),
                      ),
                    for (final entry in entries) _event(context, entry),
                  ],
                ),
              ),
              if (_offset > 0 || hasNext)
                NiraPagination(
                  page: _offset ~/ limit + 1,
                  pageCount: (total / limit).ceil(),
                  onPrevious: _offset > 0 ? () => _load(_offset - limit) : null,
                  onNext: hasNext ? () => _load(_offset + limit) : null,
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _event(BuildContext context, Json entry) {
    final before = entry['before'] as Json?;
    final after = entry['after'] as Json;
    final time = DateTime.parse(entry['occurredAt'] as String).toLocal();
    final labels = MaterialLocalizations.of(context);
    return Card(
      child: ListTile(
        title: Text(
          entry['action'] == 'created'
              ? 'Operator ditambahkan'
              : 'Operator diperbarui',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${labels.formatCompactDate(time)} · '
              '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time))}',
            ),
            if (before == null)
              Text('${after['displayName']} · ${_status(after)}')
            else ...[
              if (before['displayName'] != after['displayName'])
                Text('${before['displayName']} → ${after['displayName']}'),
              if (before['isActive'] != after['isActive'])
                Text('${_status(before)} → ${_status(after)}'),
            ],
            SelectableText('ID akun ${entry['actorId']}'),
          ],
        ),
      ),
    );
  }

  String _status(Json state) =>
      state['isActive'] == true ? 'Aktif' : 'Nonaktif';
}
