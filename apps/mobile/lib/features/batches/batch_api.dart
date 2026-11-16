import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _useFixture = bool.fromEnvironment('USE_LOCAL_FIXTURE', defaultValue: false);

class BatchApi {
  BatchApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _scope = {
    'x-dev-user-id': 'demo-user',
    'x-dev-tenant-id': 'tenant-demo',
    'x-dev-factory-id': 'factory-demo',
    'x-dev-role': 'owner',
  };

  Future<List<BatchSummary>> list() async {
    if (_useFixture || _apiBaseUrl.isEmpty) return BatchSummary.fixture;
    final response = await _client.get(Uri.parse('$_apiBaseUrl/batches'), headers: _scope);
    if (response.statusCode >= 400) throw Exception('API batch gagal (${response.statusCode})');
    return (jsonDecode(response.body) as List).map((item) => BatchSummary.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<BatchDetail> detail(String id) async {
    if (_useFixture || _apiBaseUrl.isEmpty) return BatchDetail.fixture.firstWhere((item) => item.id == id);
    final response = await _client.get(Uri.parse('$_apiBaseUrl/batches/$id'), headers: _scope);
    if (response.statusCode >= 400) throw Exception('Detail batch gagal (${response.statusCode})');
    final detail = BatchDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    final trace = await _client.get(Uri.parse('$_apiBaseUrl/batches/$id/traceability'), headers: _scope);
    if (trace.statusCode >= 400) throw Exception('Traceability batch gagal (${trace.statusCode})');
    return detail.withTrace(jsonDecode(trace.body) as Map<String, dynamic>);
  }
}

class BatchSummary {
  const BatchSummary({required this.id, required this.status, required this.kloterId, required this.totalNiraMl});
  final String id;
  final String status;
  final String kloterId;
  final int totalNiraMl;
  factory BatchSummary.fromJson(Map<String, dynamic> json) => BatchSummary(id: json['id'] as String, status: json['status'] as String, kloterId: json['kloterId'] as String, totalNiraMl: ((json['contributions'] as List?) ?? const []).fold<int>(0, (sum, item) => sum + ((item as Map<String, dynamic>)['volumeMl'] as int? ?? 0)));
  static const fixture = [
    BatchSummary(id: 'batch-normal', status: 'COOKED', kloterId: 'kloter-101', totalNiraMl: 100000),
    BatchSummary(id: 'batch-mixed', status: 'DRAFT', kloterId: 'kloter-102 + kloter-103', totalNiraMl: 100000),
    BatchSummary(id: 'batch-weighed', status: 'WEIGHED', kloterId: 'kloter-104', totalNiraMl: 95000),
    BatchSummary(id: 'batch-graded', status: 'GRADED', kloterId: 'kloter-105', totalNiraMl: 105000),
    BatchSummary(id: 'batch-rework', status: 'GRADED', kloterId: 'kloter-106', totalNiraMl: 90000),
  ];
}

class BatchDetail {
  const BatchDetail({required this.id, required this.status, required this.contributions, this.cooking, this.weighing, this.grading, this.reworks = const []});
  final String id;
  final String status;
  final List<ContributionView> contributions;
  final Map<String, dynamic>? cooking;
  final Map<String, dynamic>? weighing;
  final Map<String, dynamic>? grading;
  final List<Map<String, dynamic>> reworks;
  final Map<String, dynamic>? traceability;
  factory BatchDetail.fromJson(Map<String, dynamic> json) => BatchDetail(id: json['id'] as String, status: json['status'] as String, contributions: ((json['contributions'] as List?) ?? const []).map((item) => ContributionView.fromJson(item as Map<String, dynamic>)).toList(), cooking: json['cooking'] as Map<String, dynamic>?, weighing: json['weighing'] as Map<String, dynamic>?, grading: json['grading'] as Map<String, dynamic>?, reworks: ((json['reworks'] as List?) ?? const []).cast<Map<String, dynamic>>(), traceability: json['traceability'] as Map<String, dynamic>?);
  BatchDetail withTrace(Map<String, dynamic> value) => BatchDetail(id: id, status: status, contributions: contributions, cooking: cooking, weighing: weighing, grading: grading, reworks: reworks, traceability: value);
  static final fixture = BatchSummary.fixture.map((summary) => BatchDetail(id: summary.id, status: summary.status, contributions: summary.id == 'batch-mixed' ? const [ContributionView('kloter-102', 20000), ContributionView('kloter-103', 80000)] : [ContributionView('kloter-101', summary.totalNiraMl)], cooking: summary.status == 'COOKED' ? const {'startedAt': '2026-01-01T00:00:00Z'} : null, weighing: summary.status == 'WEIGHED' || summary.status == 'GRADED' ? const {'sugarWeightGrams': 1250000} : null, grading: summary.status == 'GRADED' ? const {'gradeCode': 'A'} : null, reworks: summary.id == 'batch-rework' ? const [{'weightGrams': 10000, 'receivingBatchId': 'batch-graded', 'status': 'RECORDED'}] : const [])).toList();
}

class ContributionView {
  const ContributionView(this.kloterId, this.volumeMl);
  final String kloterId;
  final int volumeMl;
  factory ContributionView.fromJson(Map<String, dynamic> json) => ContributionView(json['kloterId'] as String, json['volumeMl'] as int);
}
