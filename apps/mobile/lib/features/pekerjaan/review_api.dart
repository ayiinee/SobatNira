import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const reviewApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:3000',
);
const supabaseProject = String.fromEnvironment('SUPABASE_URL');
const supabasePublicKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
);
const _explicitConnectedMode =
    String.fromEnvironment('SOBATNIRA_MODE') == 'connected';
const connectedMobile =
    _explicitConnectedMode || supabaseProject != '' || supabasePublicKey != '';

typedef Json = Map<String, dynamic>;

class FactoryScope {
  FactoryScope.fromJson(Json row)
    : tenantId = row['tenantId'] as String,
      tenantName = row['tenantName'] as String,
      factoryId = row['factoryId'] as String,
      factoryName = row['factoryName'] as String;

  final String tenantId;
  final String tenantName;
  final String factoryId;
  final String factoryName;

  List<String> get _lots => [
    'tenants',
    tenantId,
    'factories',
    factoryId,
    'lots',
  ];
}

String documentType(Object? type) => switch (type) {
  'TRUCK_ARRIVAL_NOTE' => 'Nota Kedatangan Truk',
  'PRODUCTION_NOTE' => 'Nota Produksi',
  _ => 'Nota belum dikenali',
};

class ReviewApiError implements Exception {
  const ReviewApiError(this.status);
  final int status;

  String get message => switch (status) {
    401 => 'Sesi masuk telah berakhir.',
    403 || 404 => 'Data tidak tersedia untuk akun ini.',
    409 => 'Periksa konflik atau muat ulang revisi sebelum melanjutkan.',
    400 => 'Periksa nilai yang dimasukkan.',
    _ => 'Layanan SobatNira belum dapat dihubungi.',
  };
}

class ReviewApi {
  ReviewApi(this._token, {http.Client? client, this.baseUrl = reviewApiBase})
    : _client = client ?? http.Client();

  final String _token;
  final http.Client _client;
  final String baseUrl;

  static List<String> get invalidConfiguration => [
    if (!_validOrigin(supabaseProject)) 'SUPABASE_URL',
    if (supabasePublicKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    if (!_validOrigin(reviewApiBase) ||
        (_explicitConnectedMode && !const bool.hasEnvironment('API_BASE_URL')))
      'API_BASE_URL',
  ];

  static Future<ReviewApi> signIn(String email, String password) async {
    if (invalidConfiguration.isNotEmpty) throw const ReviewApiError(503);
    final uri = Uri.parse(supabaseProject).replace(
      path: '/auth/v1/token',
      queryParameters: {'grant_type': 'password'},
    );
    final response = await http
        .post(
          uri,
          headers: {
            'apikey': supabasePublicKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw ReviewApiError(response.statusCode);
    final token = (jsonDecode(response.body) as Json)['access_token'];
    if (token is! String || token.isEmpty) throw const ReviewApiError(401);
    return ReviewApi(token);
  }

  static bool _validOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '::1'].contains(uri.host)));
  }

  Uri _url(String endpoint, [Map<String, String>? query]) => Uri.parse(
    baseUrl,
  ).replace(path: '/api/v1/mobile/$endpoint', queryParameters: query);

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  Future<Json> _json(Future<http.Response> request) async {
    final response = await request.timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw ReviewApiError(response.statusCode);
    return jsonDecode(response.body) as Json;
  }

  Future<Json> _productionGet(
    List<String> path, {
    Map<String, String>? query,
  }) => _json(
    _client.get(
      Uri.parse(
        baseUrl,
      ).replace(pathSegments: ['', ...path], queryParameters: query),
      headers: _headers,
    ),
  );

  Future<List<FactoryScope>> factories() async {
    final response = await _productionGet(['auth', 'me']);
    return (response['access'] as List)
        .cast<Json>()
        .map(FactoryScope.fromJson)
        .toList();
  }

  Future<Json> lots(
    FactoryScope scope, {
    required int offset,
    required String search,
  }) => _productionGet(
    scope._lots,
    query: {
      'limit': '20',
      'offset': '$offset',
      if (search.isNotEmpty) 'q': search,
    },
  );

  Future<Json> lot(FactoryScope scope, String id) =>
      _productionGet([...scope._lots, id]);

  Future<Json> juice(FactoryScope scope, String id) =>
      _productionGet([...scope._lots, id, 'juice', 'availability']);

  Future<List<Json>> list(String status, int page, {String? factoryId}) async {
    final response = await _json(
      _client.get(
        _url('review-tasks', {
          'status': status,
          'page': '$page',
          'page_size': '20',
          'factory_id': ?factoryId,
        }),
        headers: _headers,
      ),
    );
    return (response['items'] as List).cast<Json>();
  }

  Future<Json> detail(String id) =>
      _json(_client.get(_url('review-tasks/$id'), headers: _headers));

  Future<Json> intakeLots(String taskId, int offset, {bool milling = false}) =>
      _json(
        _client.get(
          _url('review-tasks/$taskId/${milling ? 'milling' : 'intake'}-lots', {
            'offset': '$offset',
          }),
          headers: _headers,
        ),
      );

  Future<int> unreadNotifications({String? factoryId}) async {
    final response = await _json(
      _client.get(
        _url(
          'review-notifications',
          factoryId == null ? null : {'factory_id': factoryId},
        ),
        headers: _headers,
      ),
    );
    return response['unread_count'] as int;
  }

  Future<void> markNotificationRead(String taskId) async {
    await _json(
      _client.patch(
        _url('review-notifications/$taskId/read'),
        headers: _headers,
      ),
    );
  }

  Future<Uint8List> photo(String id, String asset) async {
    final response = await _client
        .get(_url('review-tasks/$id/assets/$asset'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw ReviewApiError(response.statusCode);
    return response.bodyBytes;
  }

  Future<Json> change(
    Json task,
    String action,
    Json values, {
    required String key,
  }) async {
    final request = http.Request(
      action == 'draft' ? 'PATCH' : 'POST',
      _url('documents/${task['document_id']}/$action'),
    );
    request.headers.addAll({
      ..._headers,
      'Content-Type': 'application/json',
      'Idempotency-Key': key,
    });
    request.body = jsonEncode({
      'revision_id': task['revision_id'],
      'expected_version': task['version'],
      ...values,
    });
    return _json(_client.send(request).then(http.Response.fromStream));
  }

  static String actionKey() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  void close() => _client.close();
}
