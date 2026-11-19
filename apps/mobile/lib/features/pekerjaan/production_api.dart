import 'review_api.dart';

class JuiceApi {
  JuiceApi(this.api);
  final ReviewApi api;

  Future<Json> availability(FactoryScope scope, String lotId) =>
      api.juice(scope, lotId);
  Future<Json> transfer(FactoryScope scope, String lotId, JuiceTransferRequest request) =>
      api.transferJuice(scope, lotId, request);
  Future<Json> reserve(FactoryScope scope, String lotId, Json body) =>
      api.writeProduction([...scope.lotsPath(lotId), 'juice', 'reservations'], body, requestId: body['requestId'] as String?);
  Future<Json> consume(FactoryScope scope, String lotId, String requestId) =>
      api.writeProduction([...scope.lotsPath(lotId), 'juice', 'reservations', requestId, 'consume'], {}, expectedStatus: 200);
  Future<Json> release(FactoryScope scope, String lotId, String requestId) =>
      api.writeProduction([...scope.lotsPath(lotId), 'juice', 'reservations', requestId, 'release'], {}, expectedStatus: 200);
}

class ClosureApi {
  ClosureApi(this.api);
  final ReviewApi api;
  Future<Json> check(FactoryScope scope, String lotId) => api.lotClosure(scope, lotId);
  Future<Json> history(FactoryScope scope, String lotId, {int offset = 0}) => api.lotClosureHistory(scope, lotId, offset: offset);
  Future<Json> close(FactoryScope scope, String lotId) => api.changeLotClosure(scope, lotId);
  Future<Json> reopen(FactoryScope scope, String lotId, String closureId, String reason) => api.changeLotClosure(scope, lotId, closureId: closureId, reason: reason);
}

class EconomicsApi {
  EconomicsApi(this.api);
  final ReviewApi api;
  Future<Json> stock(FactoryScope scope, {String? grade}) => api.getProduction(
    ['economics', 'stock', 'sugar'],
    query: {'grade': ?grade},
  );
  Future<Json> movement(FactoryScope scope, Json body) => api.writeProduction(['economics', 'stock', 'sugar', 'movements'], body, requestId: body['requestId'] as String?);
  Future<Json> correction(FactoryScope scope, Json body) => api.writeProduction(['economics', 'stock', 'sugar', 'corrections'], body, requestId: body['requestId'] as String?);
  Future<Json> summary(FactoryScope scope, String batchId) => api.getProduction(['economics', 'batches', batchId, 'economics']);
  Future<Json> allocate(FactoryScope scope, String batchId, Json body) => api.writeProduction(['economics', 'batches', batchId, 'economics', 'allocation'], body, requestId: body['requestId'] as String?);
}

class MasterDataApi {
  MasterDataApi(this.api);
  final ReviewApi api;
  Future<Json> list(FactoryScope scope, String kind) => api.getProduction(['production-masters', kind]);
  Future<Json> create(FactoryScope scope, String kind, Json body) => api.writeProduction(['production-masters', kind], body);
}

