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

class JuiceTransferRequest {
  const JuiceTransferRequest({
    required this.requestId,
    required this.toLotId,
    required this.toLabel,
    required this.originLotId,
    required this.originLabel,
    required this.quantityMl,
  });
  final String requestId;
  final String toLotId;
  final String toLabel;
  final String originLotId;
  final String originLabel;
  final String quantityMl;

  Json get body => {
    'requestId': requestId,
    'toLotId': toLotId,
    'originLotId': originLotId,
    'quantityMl': quantityMl,
  };
}

enum ProductionCatalog {
  suppliers('suppliers', 'Pemasok'),
  caneTypes('cane-types', 'Jenis tebu'),
  operators('operators', 'Operator WhatsApp');

  const ProductionCatalog(this.path, this.label);
  final String path;
  final String label;

  String get itemLabel =>
      this == operators ? 'operator WhatsApp' : label.toLowerCase();
}

class FactoryScope {
  FactoryScope.fromJson(Json row)
    : tenantId = row['tenantId'] as String,
      tenantName = row['tenantName'] as String,
      factoryId = row['factoryId'] as String,
      factoryName = row['factoryName'] as String,
      role = row['role'] as String?;

  final String tenantId;
  final String tenantName;
  final String factoryId;
  final String factoryName;
  final String? role;

  List<String> get _base => ['tenants', tenantId, 'factories', factoryId];
  List<String> get _lots => [..._base, 'lots'];
  List<String> get basePath => List.unmodifiable(_base);
  List<String> lotsPath(String lotId) => [..._lots, lotId];
}

String documentType(Object? type) => switch (type) {
  'TRUCK_ARRIVAL_NOTE' => 'Nota Kedatangan Truk',
  'PRODUCTION_NOTE' => 'Nota Produksi',
  _ => 'Nota belum dikenali',
};

class ReviewApiError implements Exception {
  const ReviewApiError(this.status, {this.authCode});

  factory ReviewApiError.fromSignInResponse(http.Response response) {
    String? authCode;
    try {
      final payload = jsonDecode(response.body);
      final code = payload is Json ? payload['error_code'] : null;
      if (code is String &&
          const {
            'invalid_credentials',
            'email_not_confirmed',
            'user_banned',
          }.contains(code)) {
        authCode = code;
      }
    } on FormatException {
      // Gateways may return a non-JSON error body.
    }
    return ReviewApiError(response.statusCode, authCode: authCode);
  }

  final int status;
  final String? authCode;

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
  final _pendingTransfers = <String, JuiceTransferRequest>{};
  void Function()? onSessionExpired;

  String _transferKey(FactoryScope scope, String lotId) =>
      '${scope.tenantId}/${scope.factoryId}/$lotId';

  JuiceTransferRequest? pendingTransfer(FactoryScope scope, String lotId) =>
      _pendingTransfers[_transferKey(scope, lotId)];

  JuiceTransferRequest prepareTransfer(
    FactoryScope scope,
    String lotId, {
    required String toLotId,
    required String toLabel,
    required String originLotId,
    required String originLabel,
    required String quantityMl,
  }) => _pendingTransfers.putIfAbsent(
    _transferKey(scope, lotId),
    () => JuiceTransferRequest(
      requestId: _requestUuid(),
      toLotId: toLotId,
      toLabel: toLabel,
      originLotId: originLotId,
      originLabel: originLabel,
      quantityMl: quantityMl,
    ),
  );

  Future<Json> transferJuice(
    FactoryScope scope,
    String lotId,
    JuiceTransferRequest transfer,
  ) async {
    try {
      final receipt = await _productionWrite([
        ...scope._lots,
        lotId,
        'juice',
        'transfers',
      ], transfer.body);
      if (receipt['requestId'] != transfer.requestId) {
        throw const FormatException('Transfer receipt does not match.');
      }
      _pendingTransfers.remove(_transferKey(scope, lotId));
      return receipt;
    } on ReviewApiError catch (error) {
      if (error.status == 400 || error.status == 409) {
        _pendingTransfers.remove(_transferKey(scope, lotId));
      }
      rethrow;
    }
  }

  static String _requestUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static List<String> get invalidConfiguration => [
    if (!_validOrigin(supabaseProject)) 'SUPABASE_URL',
    if (supabasePublicKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    if (!const bool.hasEnvironment('API_BASE_URL') ||
        !_validOrigin(reviewApiBase))
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
    if (response.statusCode != 200) {
      throw ReviewApiError.fromSignInResponse(response);
    }
    final payload = jsonDecode(response.body);
    final token = payload is Json ? payload['access_token'] : null;
    if (token is! String || token.isEmpty) throw const ReviewApiError(503);
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

  Future<Json> _json(
    Future<http.Response> request, {
    int expectedStatus = 200,
  }) async {
    final response = await request.timeout(const Duration(seconds: 10));
    _requireStatus(response, expectedStatus);
    return jsonDecode(response.body) as Json;
  }

  void _requireStatus(http.Response response, int expectedStatus) {
    final status = response.statusCode;
    if (status == expectedStatus) return;
    if (status == 401) onSessionExpired?.call();
    throw ReviewApiError(status);
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

  Future<Json> getProduction(List<String> path, {Map<String, String>? query}) =>
      _productionGet(path, query: query);

  Future<List<FactoryScope>> factories() async {
    final response = await _productionGet(['auth', 'me']);
    return (response['access'] as List)
        .cast<Json>()
        .map(FactoryScope.fromJson)
        .toList();
  }

  Future<Json> productionReport(
    FactoryScope scope, {
    DateTime? from,
    DateTime? before,
    bool synthetic = false,
  }) => _productionGet(
    [...scope._base, 'production', 'production-report'],
    query: {
      'synthetic': '$synthetic',
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
    },
  );

  Future<Json> profitReport(
    FactoryScope scope, {
    DateTime? from,
    DateTime? before,
    bool synthetic = false,
  }) => _productionGet(
    [...scope._base, 'production', 'profit-report'],
    query: {
      'synthetic': '$synthetic',
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
    },
  );

  Future<Json> lots(
    FactoryScope scope, {
    required int offset,
    required String search,
    int limit = 20,
    bool includeSummary = false,
  }) => _productionGet(
    scope._lots,
    query: {
      'limit': '$limit',
      'offset': '$offset',
      if (includeSummary) 'includeSummary': 'true',
      if (search.isNotEmpty) 'q': search,
    },
  );

  Future<Json> lot(FactoryScope scope, String id) =>
      _productionGet([...scope._lots, id]);

  Future<Json> juice(FactoryScope scope, String id) =>
      _productionGet([...scope._lots, id, 'juice', 'availability']);

  Future<Json> catalog(
    FactoryScope scope,
    ProductionCatalog kind, {
    int offset = 0,
    String search = '',
    bool? active,
  }) => _productionGet(
    [...scope._base, kind.path],
    query: {
      'limit': '20',
      'offset': '$offset',
      if (search.isNotEmpty) 'q': search,
      if (active != null) 'isActive': '$active',
    },
  );

  Future<Json> _productionWrite(List<String> path, Json values, {String? id}) {
    final request = http.Request(
      id == null ? 'POST' : 'PATCH',
      Uri.parse(baseUrl).replace(pathSegments: ['', ...path, ?id]),
    );
    request.headers.addAll({..._headers, 'Content-Type': 'application/json'});
    request.body = jsonEncode(values);
    return _json(
      _client.send(request).then(http.Response.fromStream),
      expectedStatus: id == null ? 201 : 200,
    );
  }

  Future<Json> writeProduction(
    List<String> path,
    Json values, {
    String? id,
    String? requestId,
    int? expectedStatus,
  }) {
    final request = http.Request(
      id == null ? 'POST' : 'PATCH',
      Uri.parse(baseUrl).replace(pathSegments: ['', ...path, ?id]),
    );
    request.headers.addAll({
      ..._headers,
      'Content-Type': 'application/json',
      if (requestId != null) 'idempotency-key': requestId,
    });
    request.body = jsonEncode(values);
    return _json(
      _client.send(request).then(http.Response.fromStream),
      expectedStatus: expectedStatus ?? (id == null ? 201 : 200),
    );
  }

  Future<Json> saveCatalog(
    FactoryScope scope,
    ProductionCatalog kind,
    Json values, {
    String? id,
  }) => _productionWrite([...scope._base, kind.path], values, id: id);

  Future<Json> operatorHistory(
    FactoryScope scope,
    String operatorId, {
    required int offset,
  }) => _productionGet(
    [...scope._base, ProductionCatalog.operators.path, operatorId, 'history'],
    query: {'limit': '20', 'offset': '$offset'},
  );

  Future<Json> saveLot(FactoryScope scope, Json values, {String? id}) =>
      _productionWrite(scope._lots, values, id: id);

  Future<Json> lotClosure(FactoryScope scope, String lotId) =>
      _productionGet([...scope._lots, lotId, 'closure']);

  Future<Json> lotClosureHistory(
    FactoryScope scope,
    String lotId, {
    int offset = 0,
  }) => _productionGet(
    [...scope._lots, lotId, 'closure', 'history'],
    query: {'limit': '20', 'offset': '$offset'},
  );

  Future<Json> changeLotClosure(
    FactoryScope scope,
    String lotId, {
    String? closureId,
    String? reason,
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse(baseUrl).replace(
        pathSegments: [
          '',
          ...scope._lots,
          lotId,
          'closure',
          if (closureId != null) 'reopen',
        ],
      ),
    );
    request.headers.addAll({..._headers, 'Content-Type': 'application/json'});
    request.body = jsonEncode(
      closureId == null
          ? <String, dynamic>{}
          : {'closureId': closureId, 'reason': reason},
    );
    return _json(_client.send(request).then(http.Response.fromStream));
  }

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
    _requireStatus(response, 200);
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

  void close() {
    onSessionExpired = null;
    _client.close();
  }
}
