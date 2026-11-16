import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/main_demo.dart';

void main() {
  testWidgets('loads the synthetic draft and retries an unavailable API', (
    tester,
  ) async {
    var requests = 0;
    final client = MockClient((request) async {
      expect(request.url.path, '/demo/draft');
      if (++requests == 1) return http.Response('', 503);
      return http.Response(
        jsonEncode({
          'synthetic': true,
          'stage': 'Penerimaan Tebu',
          'lotCode': 'DEMO-261114-01',
          'supplier': 'Pemasok Demo',
          'netWeightKg': 1250,
        }),
        200,
      );
    });

    await tester.pumpWidget(SobatNiraIntegrationDemo(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Coba lagi'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Draf sintetis'), findsOneWidget);
    expect(find.text('Penerimaan Tebu · DEMO-261114-01'), findsOneWidget);
    expect(find.text('Pemasok Demo · 1250 kg'), findsOneWidget);
    expect(requests, 2);
  });
}
