import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

class BatchApi {
  BatchApi({http.Client? client, String role = 'owner'})
    : _client = client ?? http.Client(), _role = role;
  final http.Client _client;
  final String _role;
  static final _fixtureDetails = <String, BatchDetail>{
    for (final item in BatchDetail.fixture) item.id: item,
  };
  Map<String, String> get _scope => {
    'x-dev-user-id': 'demo-user',
    'x-dev-tenant-id': 'tenant-demo',
    'x-dev-factory-id': 'factory-demo',
    'x-dev-role': _role,
  };

  Future<Map<String, dynamic>> _write(String path, Map<String, dynamic> body, {String? requestId}) async {
    if (_apiBaseUrl.isEmpty) {
      final parts = path.split('/');
      final id = parts.length > 2 ? parts[2] : null;
      final current = id == null ? null : _fixtureDetails[id];
      if (current != null) {
        final status = path.endsWith('/cooking') ? 'COOKED' : path.endsWith('/weighing') ? 'WEIGHED' : path.endsWith('/grading') ? 'GRADED' : current.status;
        _fixtureDetails[id!] = BatchDetail(id: current.id, status: status, contributions: current.contributions, cooking: status == 'COOKED' ? (current.cooking ?? body) : current.cooking, weighing: body['sugarWeightKg'] == null ? current.weighing : body, grading: body['gradeCode'] == null ? current.grading : body, reworks: current.reworks, traceability: current.traceability);
      }
      return body;
    }
    final response = await _client.post(Uri.parse('$_apiBaseUrl$path'), headers: {..._scope, 'Content-Type': 'application/json', if (requestId != null) 'idempotency-key': requestId}, body: jsonEncode(body));
    if (response.statusCode >= 400) throw Exception('API produksi gagal (${response.statusCode})');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body, {String? requestId}) => _write('/batches', body, requestId: requestId);
  Future<void> resetFixture() async {
    if (_apiBaseUrl.isEmpty) {
      _fixtureDetails
        ..clear()
        ..addEntries((BatchDetail.fixture).map((item) => MapEntry(item.id, item)));
      return;
    }
    final response = await _client.post(Uri.parse('$_apiBaseUrl/batches/fixture/reset'));
    if (response.statusCode >= 400) throw Exception('Reset fixture gagal (${response.statusCode})');
  }
  Future<Map<String, dynamic>> contribution(String id, Map<String, dynamic> body, {String? requestId}) => _write('/batches/$id/contributions', body, requestId: requestId);
  Future<Map<String, dynamic>> cooking(String id, Map<String, dynamic> body, {String? requestId}) => _write('/batches/$id/cooking', body, requestId: requestId);
  Future<Map<String, dynamic>> weighing(String id, {required double sugarWeightKg, double? caneWeightKg, String? occurredAt, String? requestId}) => _write('/batches/$id/weighing', {'sugarWeightKg': sugarWeightKg, if (caneWeightKg != null) 'caneWeightKg': caneWeightKg, if (occurredAt != null) 'occurredAt': occurredAt}, requestId: requestId);
  Future<Map<String, dynamic>> grading(String id, String gradeCode, {String? occurredAt, String? requestId}) => _write('/batches/$id/grading', {'gradeCode': gradeCode, if (occurredAt != null) 'occurredAt': occurredAt}, requestId: requestId);
  Future<Map<String, dynamic>> rework(String id, String receivingBatchId, double weightKg, {String? occurredAt, String? requestId}) => _write('/batches/$id/reworks', {'receivingBatchId': receivingBatchId, 'weightKg': weightKg, if (occurredAt != null) 'occurredAt': occurredAt}, requestId: requestId);
  Future<Map<String, dynamic>> economics(String id) async {
    if (_apiBaseUrl.isEmpty) return {'batchId': id, 'allocations': const [], 'totals': {'costRupiah': 0, 'revenueRupiah': 0, 'marginRupiah': 0}};
    final response = await _client.get(Uri.parse('$_apiBaseUrl/economics/batches/$id/economics'), headers: _scope);
    if (response.statusCode >= 400) throw Exception('Economics gagal (${response.statusCode})');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<BatchSummary>> list() async {
    if (_apiBaseUrl.isEmpty) return _fixtureDetails.values.map((item) => BatchSummary(id: item.id, status: item.status, kloterId: item.contributions.first.kloterId, totalNiraMl: item.contributions.fold(0, (sum, item) => sum + item.volumeMl))).toList();
    final response = await _client.get(Uri.parse('$_apiBaseUrl/batches'), headers: _scope);
    if (response.statusCode >= 400) throw Exception('API batch gagal (${response.statusCode})');
    return (jsonDecode(response.body) as List).map((item) => BatchSummary.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<BatchDetail> detail(String id) async {
    if (_apiBaseUrl.isEmpty) return _fixtureDetails[id]!;
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
  const BatchDetail({required this.id, required this.status, required this.contributions, this.cooking, this.weighing, this.grading, this.reworks = const [], this.traceability});
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
