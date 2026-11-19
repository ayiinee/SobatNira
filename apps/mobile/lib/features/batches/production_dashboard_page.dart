import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../widgets/page_frame.dart';

const _dashboardApiUrl = String.fromEnvironment('API_BASE_URL');

class ProductionDashboardApi {
  ProductionDashboardApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _headers = {
    'x-dev-user-id': 'demo-user',
    'x-dev-tenant-id': 'tenant-demo',
    'x-dev-factory-id': 'factory-demo',
    'x-dev-role': 'owner',
  };

  Future<ProductionDashboard> dashboard() async {
    if (_dashboardApiUrl.isEmpty) return ProductionDashboard.fixture;
    final response = await _client.get(Uri.parse('$_dashboardApiUrl/dashboard/production'), headers: _headers);
    if (response.statusCode >= 400) throw Exception('Dashboard gagal dimuat (${response.statusCode})');
    return ProductionDashboard.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<AnalyticsPoint>> analytics() async {
    if (_dashboardApiUrl.isEmpty) return AnalyticsPoint.fixture;
    final response = await _client.get(Uri.parse('$_dashboardApiUrl/analytics/production'), headers: _headers);
    if (response.statusCode >= 400) throw Exception('Analitik gagal dimuat (${response.statusCode})');
    return (jsonDecode(response.body)['points'] as List).map((item) => AnalyticsPoint.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<String> exportCsv() async {
    if (_dashboardApiUrl.isEmpty) return 'batch_id,status,occurred_at,total_nira_ml,sugar_weight_grams,grade_code\n';
    final response = await _client.get(Uri.parse('$_dashboardApiUrl/exports/batches.csv'), headers: _headers);
    if (response.statusCode >= 400) throw Exception('Ekspor gagal (${response.statusCode})');
    return response.body;
  }
}

class ProductionDashboard {
  const ProductionDashboard({required this.batchCount, required this.totalNiraMl, required this.sugarWeightKg, required this.status});
  final int batchCount;
  final int totalNiraMl;
  final double sugarWeightKg;
  final Map<String, int> status;
  factory ProductionDashboard.fromJson(Map<String, dynamic> json) => ProductionDashboard(batchCount: json['batchCount'] as int, totalNiraMl: json['totalNiraMl'] as int, sugarWeightKg: (json['officialSugarWeightKg'] as num?)?.toDouble() ?? ((json['officialSugarWeightGrams'] as num?)?.toDouble() ?? 0) / 1000, status: (json['status'] as Map<String, dynamic>).map((key, value) => MapEntry(key, value as int)));
  static const fixture = ProductionDashboard(batchCount: 5, totalNiraMl: 490000, sugarWeightKg: 3300, status: {'DRAFT': 1, 'COOKED': 1, 'WEIGHED': 1, 'GRADED': 2, 'VALIDATED': 0});
}

class AnalyticsPoint {
  const AnalyticsPoint(this.date, this.batchCount, this.niraMl, this.sugarWeightGrams);
  final String date;
  final int batchCount;
  final int niraMl;
  final int sugarWeightGrams;
  factory AnalyticsPoint.fromJson(Map<String, dynamic> json) => AnalyticsPoint(json['date'] as String, json['batchCount'] as int, json['niraMl'] as int, json['sugarWeightGrams'] as int);
  static const fixture = [AnalyticsPoint('2026-01-01', 5, 490000, 3300000)];
}

class ProductionDashboardPage extends StatefulWidget {
  ProductionDashboardPage({super.key, ProductionDashboardApi? api}) : api = api ?? ProductionDashboardApi();
  final ProductionDashboardApi api;
  @override
  State<ProductionDashboardPage> createState() => _ProductionDashboardPageState();
}

class _ProductionDashboardPageState extends State<ProductionDashboardPage> {
  late Future<(ProductionDashboard, List<AnalyticsPoint>)> _future = _load();
  Future<(ProductionDashboard, List<AnalyticsPoint>)> _load() async => (await widget.api.dashboard(), await widget.api.analytics());
  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => NiraPageScaffold(
    title: const Text('Dashboard produksi'),
    body: FutureBuilder<(ProductionDashboard, List<AnalyticsPoint>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: FilledButton(onPressed: _retry, child: const Text('Coba lagi')));
        final dashboard = snapshot.data!.$1;
        final points = snapshot.data!.$2;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [Expanded(child: _Metric('Batch', '${dashboard.batchCount}')), const SizedBox(width: 8), Expanded(child: _Metric('Nira', '${(dashboard.totalNiraMl / 1000).toStringAsFixed(0)} L')), const SizedBox(width: 8), Expanded(child: _Metric('Gula', '${dashboard.sugarWeightKg.toStringAsFixed(0)} Kg'))]),
          const SizedBox(height: 16),
          _Panel(title: 'Status batch', child: Wrap(spacing: 8, runSpacing: 8, children: dashboard.status.entries.map((entry) => Chip(label: Text('${entry.key}: ${entry.value}'))).toList())),
          _Panel(title: 'Analitik harian', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: points.map((point) => Text('${point.date}: ${point.batchCount} batch • ${(point.niraMl / 1000).toStringAsFixed(0)} L nira • ${(point.sugarWeightGrams / 1000).toStringAsFixed(0)} Kg gula')).toList())),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: () async { final messenger = ScaffoldMessenger.of(context); try { final csv = await widget.api.exportCsv(); if (mounted) messenger.showSnackBar(SnackBar(content: Text('Ekspor siap (${csv.length} karakter)'))); } catch (error) { if (mounted) messenger.showSnackBar(SnackBar(content: Text('$error'))); } }, icon: const Icon(Icons.download), label: const Text('Siapkan ekspor CSV')),
        ]);
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [Text(label), const SizedBox(height: 4), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))])));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), child])));
}

