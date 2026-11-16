import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'batch_api.dart';
import 'production_dashboard_page.dart';

class BatchListPage extends StatefulWidget {
  BatchListPage({super.key, BatchApi? api}) : api = api ?? BatchApi();
  final BatchApi api;
  @override
  State<BatchListPage> createState() => _BatchListPageState();
}

class _BatchListPageState extends State<BatchListPage> {
  late Future<List<BatchSummary>> _future = widget.api.list();
  String? _status;
  void _retry() => setState(() => _future = widget.api.list());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Batch produksi'), backgroundColor: niraGreen, foregroundColor: Colors.white, actions: [IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductionDashboardPage())), icon: const Icon(Icons.insights), tooltip: 'Dashboard')]),
    body: FutureBuilder<List<BatchSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _ErrorState(onRetry: _retry);
        final batches = snapshot.data!.where((item) => _status == null || item.status == _status).toList();
        return Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Filter status', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem<String>(child: Text('Semua')),
              DropdownMenuItem(value: 'DRAFT', child: Text('DRAFT')),
              DropdownMenuItem(value: 'COOKED', child: Text('COOKED')),
              DropdownMenuItem(value: 'WEIGHED', child: Text('WEIGHED')),
              DropdownMenuItem(value: 'GRADED', child: Text('GRADED')),
              DropdownMenuItem(value: 'VALIDATED', child: Text('VALIDATED')),
            ],
            onChanged: (value) => setState(() => _status = value),
          )),
          Expanded(child: batches.isEmpty ? const Center(child: Text('Batch tidak ditemukan')) : ListView.builder(
            itemCount: batches.length,
            itemBuilder: (context, index) {
              final batch = batches[index];
              return ListTile(
                title: Text(batch.id),
                subtitle: Text('${batch.kloterId} â€¢ ${(batch.totalNiraMl / 1000).toStringAsFixed(0)} L'),
                trailing: Chip(label: Text(batch.status)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BatchDetailPage(id: batch.id, api: widget.api))),
              );
            },
          )),
        ]);
      },
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Batch gagal dimuat'), const SizedBox(height: 8), FilledButton(onPressed: onRetry, child: const Text('Coba lagi'))]));
}



class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({required this.id, required this.api, super.key});
  final String id;
  final BatchApi api;
  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> {
  late Future<BatchDetail> _future = widget.api.detail(widget.id);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.id), backgroundColor: const Color(0xFF174B35), foregroundColor: Colors.white),
    body: FutureBuilder<BatchDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: FilledButton(onPressed: () => setState(() => _future = widget.api.detail(widget.id)), child: const Text('Coba lagi')));
        final batch = snapshot.data!;
        final total = batch.contributions.fold<int>(0, (sum, item) => sum + item.volumeMl);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Status ${batch.status}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _Section(title: 'Sumber nira', child: Column(children: batch.contributions.map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.kloterId), subtitle: Text('${item.volumeMl} ml â€¢ ${(item.volumeMl / total * 100).toStringAsFixed(1)}%'))).toList())),
          _Section(title: 'Pemasakan', child: Text(batch.cooking == null ? 'Belum dicatat' : 'Tercatat')),
          _Section(title: 'Hasil timbang', child: Text(batch.weighing?['sugarWeightGrams'] == null ? 'Belum ditimbang' : '${batch.weighing!['sugarWeightGrams']} gram')),
          _Section(title: 'Grade', child: Text(batch.grading?['gradeCode']?.toString() ?? 'Belum grading')),
          _Section(title: 'Rework (terpisah)', child: batch.reworks.isEmpty ? const Text('Tidak ada') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: batch.reworks.map((item) => Text('${item['weightGrams']} gram ? ${item['receivingBatchId']}')).toList())),
        ]);
      },
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), child])));
}

