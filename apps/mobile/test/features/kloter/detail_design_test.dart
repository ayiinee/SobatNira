import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/batch_detail_page.dart';
import 'package:sobatnira/features/kloter/connected_production.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/kloter/detail_fields.dart';
import 'package:sobatnira/features/kloter/kloter_detail_page.dart';
import 'package:sobatnira/features/kloter/kloter_detail_widgets.dart';
import 'package:sobatnira/features/kloter/kloter_process_page.dart';
import 'package:sobatnira/features/kloter/official_batch_workflow.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';

final detailScope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': 'factory',
  'factoryName': 'Pabrik uji',
  'role': 'admin',
});

Json detailLotRecord() => {
  'id': 'lot',
  'displayCode': 'KLOTER-UJI',
  'receivedAt': '2026-11-10T02:00:00Z',
  'supplierName': 'Pemasok Uji',
  'status': 'open',
  'netWeightGrams': '1500000',
  'caneTypeCode': 'BL',
  'brix': '18.5',
  'juiceProducedLiters': '250',
  'intake': {
    'document': {'revisionNumber': 1},
  },
  'milling': {
    'document': {'revisionNumber': 1},
  },
};

Json detailBatchRecord({String status = 'approved'}) => {
  'id': 'batch',
  'lot_id': 'lot',
  'code': 'BATCH-UJI',
  'wok_number': 1,
  'status': status,
  'is_synthetic': false,
  'occurred_at': '2026-11-10T04:00:00Z',
  'quantity_ml': '83500.125',
  'physical_weight_kg': '29.25',
  'grades': [
    {'code': 'A', 'weightKg': '27', 'pricePerKgRupiah': '20000'},
  ],
  'finalSugarKg': '27',
  'exactValueRupiah': '540000',
  'costSaved': true,
  'remainingMl': '0',
};

http.Response detailResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Widget detailLotPage(ReviewApi api, DemoProduction demo) {
  final lot = connectedLot(detailLotRecord());
  return KloterDetailPage(
    kloter: lot,
    demo: demo,
    onNavigate: (_) {},
    production: OfficialLotBatches(
      api: api,
      scope: detailScope,
      lotId: 'lot',
      kloterCode: lot.code,
      caneWeight: lot.weight,
      kloter: lot,
      millingRevision: null,
      canCreate: false,
      onOpenPekerjaan: () {},
      onNavigate: (_) {},
      onChanged: () {},
      reportLink: ([id]) async {},
    ),
  );
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(
        rootBundle.load('assets/sobatnira/fonts/Inter-$weight.ttf'),
      );
    }
    await inter.load();
  });
  testWidgets('batch cards keep the repair status badge above the metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(30),
            child: Align(
              alignment: Alignment.topCenter,
              child: KloterBatchTile(
                title: 'Batch 1',
                juice: '83,5 L',
                physicalWeight: '29,25 kg',
                pending: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Batch 1')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Nira batch')).top),
    );
    expect(find.text('Tervalidasi'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets(
    'official batch uses demo fields, photo space and exact API values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction.empty();
      addTearDown(demo.dispose);
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(
            request.url.path,
            startsWith('/tenants/tenant/factories/factory/production/'),
          );
          if (request.url.path.endsWith('/production-report')) {
            return detailResponse({
              'items': [
                {
                  'lotId': 'lot',
                  'calculation': {
                    'productionMarginRupiah': '900719925474099312345',
                  },
                },
              ],
            });
          }
          return detailResponse(
            request.url.path.endsWith('/batches')
                ? {
                    'items': [detailBatchRecord()],
                  }
                : detailBatchRecord(),
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(theme: niraTheme(), home: detailLotPage(api, demo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BATCH-UJI'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchDetailPage), findsOneWidget);
      final fields = tester
          .widget<EditableFields>(find.byType(EditableFields).first)
          .fields;
      expect(fields.map((field) => field.label), batchSummaryLabels);
      expect(find.text('83,500125 L'), findsOneWidget);
      expect(find.text('18,5 °Bx'), findsOneWidget);
      expect(find.text('29,25 kg'), findsOneWidget);
      expect(
        fields.singleWhere((field) => field.label == 'Jam turun').value,
        '—',
      );
      expect(
        fields.singleWhere((field) => field.label == 'Bagian kloter').value,
        '—',
      );
      final preview = tester.getSize(find.byType(ApprovedDocumentPreview));
      expect(preview.width / preview.height, closeTo(2.4, .01));
      expect(find.textContaining('Margin kumulatif kloter'), findsNothing);
      expect(find.text('Rp540.000'), findsOneWidget);
      expect(
        tester.getTopRight(find.text('Rp540.000')).dx,
        closeTo(tester.getTopRight(find.text('Harga')).dx, 0.1),
      );
      expect(find.text('Status biaya'), findsNothing);
      await tester.tap(find.text('Masak'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableFields>(find.byType(EditableFields))
            .fields
            .map((field) => field.label),
        batchCookingLabels,
      );
      expect(find.text('Pemasok Uji'), findsOneWidget);
      expect(find.text('Foto pemasakan'), findsOneWidget);
      await tester.tap(find.text('Grade'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopRight(find.text('Rp20.000/Kg')).dx,
        closeTo(tester.getTopRight(find.text('Harga')).dx, 0.1),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('27 kg'), findsNothing);
      expect(find.text('Hasil fisik'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final status in ['draft', 'approved']) {
    testWidgets('legacy API opens $status batch detail without write actions', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction.empty();
      addTearDown(demo.dispose);
      final batch = detailBatchRecord(status: status)
        ..remove('grades')
        ..remove('finalSugarKg')
        ..remove('exactValueRupiah')
        ..remove('costSaved')
        ..remove('remainingMl');
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path.endsWith('/batches')) {
            return detailResponse({
              'items': [batch],
            });
          }
          if (request.url.path.endsWith('/production-report')) {
            return detailResponse({
              'items': [
                {
                  'lotId': 'lot',
                  'batches': [
                    {...detailBatchRecord(), 'id': 'other'},
                    if (status == 'approved') detailBatchRecord(),
                  ],
                },
              ],
            });
          }
          expect(request.url.path, endsWith('/production/batches/batch'));
          return http.Response(
            jsonEncode({'message': 'Cannot GET ${request.url.path}'}),
            404,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(theme: niraTheme(), home: detailLotPage(api, demo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BATCH-UJI'));
      await tester.pumpAndSettle();
      expect(find.text('83,500125 L'), findsOneWidget);
      expect(find.text('29,25 kg'), findsOneWidget);
      expect(find.text('Muat ulang batch'), findsNothing);
      expect(find.byTooltip('Buka koreksi batch'), findsNothing);
      if (status == 'draft') {
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Validasi'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Validasi belum tersedia pada versi API ini.'),
          findsOneWidget,
        );
      } else {
        expect(find.text('Validasi'), findsNothing);
      }
      expect(find.text('Isi biaya kloter'), findsNothing);
      await tester.tap(find.text('Masak'));
      await tester.pumpAndSettle();
      expect(find.text('10 November 2026'), findsOneWidget);
      await tester.tap(find.text('Grade'));
      await tester.pumpAndSettle();
      expect(
        find.text('Rp540.000'),
        status == 'approved' ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets(
    'validation still uses the scoped backend after changing the design',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction.empty();
      addTearDown(demo.dispose);
      var status = 'draft';
      Json? correction;
      String? closureId;
      var physicalWeight = '29.25';
      final writes = <String>[];
      var detailReads = 0;
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          final path = request.url.path;
          if (request.method != 'GET') {
            writes.add(path);
            expect(request.headers['Authorization'], 'Bearer fixture');
            if (path.contains('/corrections/')) {
              final values = jsonDecode(request.body) as Json;
              if (request.method == 'PATCH') {
                expect(values['version'], 1);
                correction = {
                  ...correction!,
                  'version': 2,
                  'proposed_data': {
                    'physicalWeightKg': values['physicalWeightKg'],
                    'grades': values['grades'],
                  },
                };
                return detailResponse(correction!);
              }
              if (path.endsWith('/approve')) {
                expect(values['version'], 2);
                physicalWeight =
                    (correction!['proposed_data'] as Json)['physicalWeightKg']
                        as String;
                correction = null;
                return detailResponse({});
              }
              if (path.endsWith('/discard')) {
                expect(values['version'], 1);
                correction = null;
                return detailResponse({});
              }
              expect(values, {
                'reason': 'Koreksi batch dikonfirmasi melalui aplikasi.',
                'reopenClosureId': ?closureId,
              });
              closureId = null;
              correction = {
                'id': path.split('/').last,
                'version': 1,
                'reason': values['reason'],
                'proposed_data': {
                  'physicalWeightKg': physicalWeight,
                  'grades': detailBatchRecord(status: 'approved')['grades'],
                },
              };
              return http.Response(jsonEncode(correction), 201);
            }
            status = 'approved';
            closureId = 'closure-fixture';
            return detailResponse({});
          }
          if (request.url.path.endsWith('/production-report')) {
            fail(
              'Detail batch yang tersedia tidak perlu memuat laporan kloter.',
            );
          }
          if (request.url.path.endsWith('/batches/batch')) detailReads++;
          return detailResponse(
            request.url.path.endsWith('/batches')
                ? {
                    'items': [
                      {
                        ...detailBatchRecord(status: status),
                        'hasCorrection': correction != null,
                      },
                    ],
                  }
                : {
                    ...detailBatchRecord(status: status),
                    'physical_weight_kg': physicalWeight,
                    'canCorrect': status == 'approved',
                    'lotClosed': closureId != null,
                    'lotClosureId': closureId,
                    'correction': correction,
                  },
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(theme: niraTheme(), home: detailLotPage(api, demo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BATCH-UJI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validasi'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Konfirmasi'));
      await tester.pumpAndSettle();
      expect(writes, [
        '/tenants/tenant/factories/factory/production/batches/batch/approve',
      ]);
      expect(find.text('Batch tervalidasi'), findsOneWidget);
      final validatedHeight = tester
          .getSize(find.widgetWithText(FilledButton, 'Batch tervalidasi'))
          .height;
      expect(find.text('BATCH-UJI berhasil divalidasi'), findsOneWidget);
      await tester.tap(find.byTooltip('Buka koreksi batch'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final correctionDialog = tester.widget<AlertDialog>(dialog);
      expect(correctionDialog.backgroundColor, Colors.white);
      expect(correctionDialog.surfaceTintColor, Colors.transparent);
      expect((correctionDialog.title as Text).data, 'Buka koreksi batch?');
      expect((correctionDialog.title as Text).textAlign, TextAlign.center);
      expect((correctionDialog.content as Text).textAlign, TextAlign.center);
      expect(
        (correctionDialog.content as Text).data,
        contains('Kloter akan dibuka kembali'),
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextFormField)),
        findsNothing,
      );
      final cancel = find.widgetWithText(OutlinedButton, 'Batal');
      final confirm = find.widgetWithText(FilledButton, 'Konfirmasi');
      expect(tester.getSize(cancel), tester.getSize(confirm));
      expect(tester.getCenter(cancel).dy, tester.getCenter(confirm).dy);
      expect(
        tester.getCenter(cancel).dx,
        lessThan(tester.getCenter(confirm).dx),
      );
      expect(writes, hasLength(1));
      expect(closureId, 'closure-fixture');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(writes, hasLength(1));
      await tester.tap(find.byTooltip('Buka koreksi batch'));
      await tester.pumpAndSettle();
      final readsBeforeOpen = detailReads;
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(detailReads, readsBeforeOpen);
      expect(find.text('Draf koreksi'), findsNothing);
      expect(find.text('Buang draf koreksi'), findsNothing);
      expect(find.text('Validasi ulang'), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(FilledButton, 'Validasi ulang'))
            .height,
        validatedHeight,
      );
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('1 Batch perlu ditinjau'), findsOneWidget);
      expect(
        tester.widget<KloterBatchTile>(find.byType(KloterBatchTile)).pending,
        isTrue,
      );
      await tester.tap(find.text('BATCH-UJI'));
      await tester.pumpAndSettle();
      final weight = find.text('Hasil timbang');
      await tester.scrollUntilVisible(weight, 150);
      await tester.tap(weight);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '28,5');
      final readsBeforeEdit = detailReads;
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(physicalWeight, '29.25');
      expect(detailReads, readsBeforeEdit);
      await tester.tap(find.text('Grade').first);
      await tester.pumpAndSettle();
      expect(find.text('Buang draf koreksi'), findsOneWidget);
      await tester.tap(find.text('Validasi ulang'));
      await tester.pumpAndSettle();
      expect(find.text('Validasi ulang BATCH-UJI?'), findsOneWidget);
      await tester.tap(find.text('Konfirmasi'));
      await tester.pumpAndSettle();
      expect(find.text('Koreksi batch berhasil divalidasi'), findsOneWidget);
      expect(find.text('Batch tervalidasi'), findsOneWidget);
      expect(physicalWeight, '28.5');
      expect(detailReads, readsBeforeEdit + 1);
      expect(writes, hasLength(4));

      await tester.tap(find.byTooltip('Buka koreksi batch'));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade').first);
      await tester.pumpAndSettle();
      final discard = find.text('Buang draf koreksi');
      await tester.ensureVisible(discard);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      final readsBeforeDiscard = detailReads;
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(detailReads, readsBeforeDiscard);
      expect(writes.last, endsWith('/discard'));
      expect(find.text('Batch tervalidasi'), findsOneWidget);
      expect(discard, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'connected intake keeps demo rows and fits narrow enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction.empty();
      addTearDown(demo.dispose);
      final lot = connectedLot(detailLotRecord());
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: KloterProcessPage(
              kloter: lot,
              demo: demo,
              onNavigate: (_) {},
              onOpenPekerjaan: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(EditableFields), 100);
      expect(
        tester
            .widget<EditableFields>(find.byType(EditableFields))
            .fields
            .map((field) => field.label),
        intakeDetailLabels,
      );
      expect(find.text('ID nota'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incomplete batch keeps the validation footer disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final demo = DemoProduction.empty();
    addTearDown(demo.dispose);
    final batch = {
      ...detailBatchRecord(status: 'draft'),
      'costSaved': false,
      'remainingMl': '83500.125',
    };
    final api = ReviewApi(
      'fixture',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/production-report')) {
          return detailResponse({'items': []});
        }
        return detailResponse(
          request.url.path.endsWith('/batches')
              ? {
                  'items': [batch],
                }
              : batch,
        );
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(theme: niraTheme(), home: detailLotPage(api, demo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('BATCH-UJI'));
    await tester.pumpAndSettle();
    final button = tester.widget<NiraButton>(
      find.widgetWithText(NiraButton, 'Validasi'),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(BatchReviewActions), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
