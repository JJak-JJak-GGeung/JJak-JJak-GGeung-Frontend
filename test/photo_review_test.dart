import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/api.dart';
import 'package:jjakjjakggeung/features/ui/photo_review.dart';
import 'package:jjakjjakggeung/features/ui/shared.dart' show qtyText, unitContainsQuantity;

class TestBackend implements Backend {
  final pending = Completer<Json>();
  final uploads = <String>[];
  final choices = <String, Json>{};
  Map<String, String> confirmed = {};
  @override
  Future<Json> upload(
    String path,
    Uint8List bytes,
    String name,
    String mime, [
    Map<String, String> fields = const {},
  ]) {
    uploads.add(path);
    if (path.endsWith('/confirm')) {
      confirmed = fields;
      return Future.value({'document_id': 'document-1', 'period_id': 'period'});
    }
    return pending.future;
  }

  @override
  Future<dynamic> get(String path) async =>
      choices[path] ?? {'stores': <Json>[]};
  @override
  Future<Json> post(String path, Json body) => throw UnimplementedError();
  @override
  Future<Uint8List> original(String documentId) => throw UnimplementedError();
}

void main() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aV8AAAAASUVORK5CYII=',
  );
  for (final wide in [false, true]) {
    testWidgets('원본은 항상 열리고 편집한 값 유지 / wide=$wide', (tester) async {
      tester.view.physicalSize = Size(wide ? 1100 : 390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = TestBackend();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PhotoReview(
              PlatformFile(
                name: 'sample.png',
                bytes: bytes,
                size: bytes.length,
              ),
              api: api,
            ),
          ),
        ),
      );
      // Narrow phones show the original button as an icon with a tooltip.
      final original =
          wide ? find.text('원본 보기') : find.byTooltip('원본 보기');
      expect(original, findsOneWidget);
      expect(find.byType(Image), wide ? findsOneWidget : findsNothing);
      await tester.tap(original);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('원본 사진'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      api.pending.complete({
        'signature': 'test',
        'draft': {
          'supplier_name_read': '샘플',
          'doc_type': 'UNKNOWN',
          'lines': [
            {
              'item': '검수 품목',
              'qty_read': '7',
              'unit': 'kg',
              'unit_price_read': '300',
              'amount_read': 2100,
            },
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('문서에서 읽은 거래처 · 샘플'), findsOneWidget);
      final qty = find.widgetWithText(TextFormField, '수량');
      await tester.scrollUntilVisible(qty, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(qty, '5');
      await tester.tap(original);
      await tester.pumpAndSettle();
      expect(find.text('원본 사진'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
      expect(api.uploads, ['/api/photo-previews']);
    });
  }
  testWidgets('판독 실패 후에도 원본을 열 수 있다', (tester) async {
    final api = TestBackend();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: PhotoReview(
                PlatformFile(
                    name: 'sample.png', bytes: bytes, size: bytes.length),
                api: api))));
    api.pending.completeError(Exception('판독 실패'));
    await tester.pumpAndSettle();
    expect(find.text('다시 판독'), findsOneWidget);
    await tester.tap(find.text('원본 보기'));
    await tester.pumpAndSettle();
    expect(find.text('원본 사진'), findsOneWidget);
    expect(api.uploads, ['/api/photo-previews']);
  });
  testWidgets('원본을 열지 않고 판독값을 고쳐 저장할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = TestBackend();
    api.choices.addAll({
      '/api/stores': {
        'stores': [
          {'id': 'store', 'name': '점포'}
        ]
      },
      '/api/suppliers?store_id=store': {
        'suppliers': [
          {'id': 'supplier', 'name': '샘플'}
        ]
      },
      '/api/periods?store_id=store&supplier_id=supplier': {
        'periods': [
          {
            'period_id': 'period',
            'period_start': '2026-01-01',
            'period_end': '2026-01-07',
            'label': '기간'
          }
        ]
      }
    });
    api.pending.complete({
      'signature': 'sig',
      'line_reference_edits': true,
      'draft': {
        'supplier_name_read': '샘플',
        'doc_type': 'DELIVERY',
        'store_name_read': '점포',
        'doc_date': '2026-01-02',
        'supply_total': 2000000,
        'tax_total': null,
        'document_total': 2000000,
        'previous_balance': null,
        'balance_after_dispatch': null,
        'deposit_amount': 25,
        'current_balance': null,
        'lines': [
          {
            'item': '채소',
            'qty_read': '4',
            'unit': 'kg',
            'spec': '1kg',
            'delivery_no': 'old',
            'item_code': '0012',
            'discount_amount_read': 0,
            'line_total_read': 9900,
          }
        ]
      }
    });
    String? destination;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Builder(
                builder: (ctx) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          destination = await Navigator.of(ctx).push<String>(
                              MaterialPageRoute(
                                  builder: (_) => PhotoReview(
                                      PlatformFile(
                                          name: 'sample.png',
                                          bytes: bytes,
                                          size: bytes.length),
                                      api: api)));
                        },
                        child: const Text('사진 선택')))))));
    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();
    expect(api.uploads, ['/api/photo-previews']);
    final extra = find.text('다른 금액 입력');
    await tester.scrollUntilVisible(extra, 180, scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(TextFormField, '공급가액 합계 (원)'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '세액 합계 (원)'), findsNothing);
    expect(find.widgetWithText(TextFormField, '현잔액 (원)'), findsNothing);
    await tester.tap(extra);
    await tester.pumpAndSettle();
    for (final entry in {'입금액 (원)': '', '세액 합계 (원)': '0'}.entries) {
      final input = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(input);
      await tester.enterText(input, entry.value);
    }
    final amountFields = [
      for (final label in statementAmountLabels.values)
        find.widgetWithText(TextFormField, '$label (원)'),
    ];
    for (var i = 1; i < amountFields.length; i++) {
      await tester.ensureVisible(amountFields[i]);
      expect(tester.getTopLeft(amountFields[i]).dy - tester.getBottomLeft(amountFields[i-1]).dy,
          greaterThanOrEqualTo(16));
    }
    final storeField = find.widgetWithText(DropdownButtonFormField<String>, '내 점포');
    await tester.ensureVisible(storeField);
    expect(tester.getTopLeft(storeField).dy - tester.getBottomLeft(amountFields.last).dy,
        greaterThanOrEqualTo(16));
    final collapse = find.text('빈 금액 칸 접기');
    await tester.ensureVisible(collapse);
    await tester.pumpAndSettle();
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '현잔액 (원)'), findsNothing);
    expect(find.widgetWithText(TextFormField, '세액 합계 (원)'), findsOneWidget);
    for (final edit in {'연결할 납품명세 번호': '', '납품·수령일 (YYYY-MM-DD)': '2026-01-02'}.entries) {
      final input = find.widgetWithText(TextFormField, edit.key);
      await tester.scrollUntilVisible(input, 180, scrollable: find.byType(Scrollable).first);
      await tester.enterText(input, edit.value);
    }
    final qty = find.widgetWithText(TextFormField, '수량');
    await tester.scrollUntilVisible(qty, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(qty, '40');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final details = find.text('품목 상세 정보');
    await tester.scrollUntilVisible(details, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    final spec = find.widgetWithText(TextFormField, '규격');
    await tester.scrollUntilVisible(spec, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(spec, '2kg');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final unit = find.widgetWithText(TextFormField, '단위');
    await tester.enterText(unit, '36kg');
    await tester.pump();
    expect(find.text('수량은 왼쪽에, 단위는 kg처럼 입력하세요.'), findsOneWidget);
    final save = find.text('판독값 확인하고 저장');
    await tester.scrollUntilVisible(save, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '판독값 확인하고 저장')).onPressed, isNull);
    expect(api.confirmed, isEmpty);
    await tester.scrollUntilVisible(unit, -180,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(unit, 'kg');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(save, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final confirmed = jsonDecode(api.confirmed['review_json']!);
    expect(confirmed['lines'][0]['qty_read'], '40');
    expect(confirmed['lines'][0]['unit'], 'kg');
    expect(confirmed['statement_amounts'], {'deposit_amount': null, 'tax_total': 0});
    expect(confirmed['lines'][0], containsPair('delivery_no', null));
    expect(confirmed['lines'][0]['delivery_date'], '2026-01-02');
    expect(confirmed['lines'][0]['spec'], '2kg');
    expect(confirmed['lines'][0]['item_code'], '0012');
    expect(confirmed['lines'][0]['discount_amount_read'], 0);
    expect(confirmed['lines'][0]['line_total_read'], 9900);
    expect(confirmed['supplier_id'], 'supplier');
    expect(destination, '/period/period/upload?document=document-1');
    expect(api.uploads, ['/api/photo-previews', '/api/photo-previews/confirm']);
  });
  test('수량과 단위는 기존 입력 오류가 있어도 구분되어 보인다', () {
    String display(String unit) => qtyText({'qty_read': '40', 'unit': unit}, 'qty_read');
    expect(display('36kg'), '40 (단위 확인 · 36kg)');
    expect(display('kg'), '40kg');
    expect(unitContainsQuantity('36 kg'), isTrue);
    expect(unitContainsQuantity('36'), isTrue);
    expect(unitContainsQuantity('m2'), isFalse);
    expect(unitContainsQuantity('10개입'), isFalse);
  });

  testWidgets('판독 다시 시도는 실패한 문서의 종류·점포·거래처·기간을 그대로 쓴다', (tester) async {
    final api = TestBackend();
    api.choices.addAll({
      '/api/stores': {
        'stores': [
          {'id': 'read-store', 'name': '읽은 점포'},
          {'id': 'kept-store', 'name': '기존 점포'},
        ]
      },
      '/api/suppliers?store_id=kept-store': {
        'suppliers': [
          {'id': 'read-supplier', 'name': '읽은 거래처'},
          {'id': 'kept-supplier', 'name': '기존 거래처'},
        ]
      },
      '/api/periods?store_id=kept-store&supplier_id=kept-supplier': {
        'periods': [
          {'period_id': 'other-week', 'period_start': '2026-03-02', 'period_end': '2026-03-08', 'label': '다른 주'},
          {'period_id': 'kept-week', 'period_start': '2026-01-05', 'period_end': '2026-01-11', 'label': '기존 주'},
        ]
      },
    });
    // GPT reads another type, store, supplier and a date in another week.
    api.pending.complete({
      'signature': 'sig',
      'draft': {
        'store_name_read': '읽은 점포',
        'supplier_name_read': '읽은 거래처',
        'doc_type': 'RECEIPT',
        'doc_date': '2026-03-03',
        'lines': [
          {'item': '채소', 'qty_read': '4', 'unit': 'kg'}
        ]
      }
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Builder(
                builder: (ctx) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(ctx).push<String>(
                            MaterialPageRoute(
                                builder: (_) => PhotoReview(
                                    PlatformFile(name: 'original.png', bytes: bytes, size: bytes.length),
                                    api: api,
                                    existing: const {
                                      'doc_type': 'DELIVERY',
                                      'store_id': 'kept-store',
                                      'supplier_id': 'kept-supplier',
                                      'period_id': 'kept-week',
                                    }))),
                        child: const Text('다시 시도')))))));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    final save = find.text('판독값 확인하고 저장');
    await tester.scrollUntilVisible(save, 180, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final confirmed = jsonDecode(api.confirmed['review_json']!);
    expect(confirmed['doc_type'], 'DELIVERY');
    expect(confirmed['store_id'], 'kept-store');
    expect(confirmed['supplier_id'], 'kept-supplier');
    expect(confirmed['period_id'], 'kept-week');
    expect(confirmed.containsKey('supplier_name'), isFalse);
  });
  testWidgets('다른 거래처 주에 보이던 실패 문서는 원래 거래처를 쓰고 주는 날짜로 고른다', (tester) async {
    final api = TestBackend();
    api.choices.addAll({
      '/api/stores': {
        'stores': [
          {'id': 'kept-store', 'name': '기존 점포'}
        ]
      },
      '/api/suppliers?store_id=kept-store': {
        'suppliers': [
          {'id': 'shown-supplier', 'name': '보던 거래처'},
          {'id': 'own-supplier', 'name': '원래 거래처'},
        ]
      },
      '/api/periods?store_id=kept-store&supplier_id=own-supplier': {
        'periods': [
          {'period_id': 'own-week', 'period_start': '2026-01-05', 'period_end': '2026-01-11', 'label': '원래 주'},
        ]
      },
    });
    api.pending.complete({
      'signature': 'sig',
      'draft': {
        'store_name_read': null,
        'supplier_name_read': '보던 거래처',
        'doc_type': 'DELIVERY',
        'doc_date': '2026-01-06',
        'lines': [
          {'item': '채소', 'qty_read': '4', 'unit': 'kg'}
        ]
      }
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: PhotoReview(
                PlatformFile(name: 'original.png', bytes: bytes, size: bytes.length),
                api: api,
                existing: const {
                  'doc_type': 'DELIVERY',
                  'store_id': 'kept-store',
                  'supplier_id': 'own-supplier',
                }))));
    await tester.pumpAndSettle();
    final save = find.text('판독값 확인하고 저장');
    await tester.scrollUntilVisible(save, 180, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final confirmed = jsonDecode(api.confirmed['review_json']!);
    expect(confirmed['supplier_id'], 'own-supplier');
    expect(confirmed['period_id'], 'own-week');
  });
  for (final mode in ['empty', 'match', 'different']) {
    final firstStore = mode != 'match';
    testWidgets('사진 한 장으로 새 거래처와 원본 확인 저장 mode=$mode',
        (tester) async {
      final api = TestBackend();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      api.choices['/api/stores'] = {
        'stores': mode == 'empty'
            ? []
            : [
                {'id': 'shop', 'name': mode == 'different' ? '기존 점포' : '우리 점포'}
              ]
      };
      api.choices['/api/suppliers?store_id=shop'] = {
        'suppliers': [
          {'id': 'old', 'name': '기존 상사'}
        ]
      };
      api.pending.complete({
        'draft': {
          'store_name_read': '우리 점포',
          'supplier_name_read': '처음 수산',
          'doc_date': '2026-11-13',
          'doc_type': 'DELIVERY',
          'lines': [
            {'item': '새 품목', 'qty_read': '2', 'unit': 'kg'}
          ]
        },
        'signature': 's'
      });
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: PhotoReview(
                  PlatformFile(
                      name: 'sample.png', size: bytes.length, bytes: bytes),
                  api: api))));
      await tester.pumpAndSettle();
      expect(api.uploads, ['/api/photo-previews']);
      if (firstStore) {
        final add = find.text('이 이름으로 새 점포 등록하기');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(api.uploads, ['/api/photo-previews']);
      }
      final tradeDate = find.widgetWithText(TextFormField, '원본 거래일');
      await tester.scrollUntilVisible(tradeDate, firstStore ? -180 : 180,
          scrollable: find.byType(Scrollable).first);
      final rawDate = switch (mode) {
        'empty' => '20260230',
        'match' => '2026.11.16',
        _ => '2026-11-16',
      };
      await tester.enterText(tradeDate, rawDate);
      final vendor = find.widgetWithText(TextFormField, '새 거래처 이름 (공급자)');
      await tester.scrollUntilVisible(vendor, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(vendor, '확인한 수산');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, firstStore ? '새 점포 등록하고 원본 저장' : '거래처 등록하고 원본 저장');
      await tester.scrollUntilVisible(save, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      if (mode == 'empty') {
        expect(api.confirmed, isEmpty);
        await tester.scrollUntilVisible(tradeDate, -180,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('실제 날짜를 연월일 8자리로 입력해 주세요.'), findsOneWidget);
        await tester.enterText(tradeDate, '20261116');
        expect(tester.widget<EditableText>(find.descendant(
          of: tradeDate, matching: find.byType(EditableText))).controller.text, '2026-11-16');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(save, 180, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
      }
      final request = jsonDecode(api.confirmed['review_json']!);
      expect(request[firstStore ? 'store_name' : 'store_id'],
          firstStore ? '우리 점포' : 'shop');
      expect(request['supplier_name'], '확인한 수산');
      expect(request['week_start'], '2026-11-09');
      expect(request['trade_date'], '2026-11-16');
      expect(request['supplier_id'], isNull);
      expect(
          api.uploads, ['/api/photo-previews', '/api/photo-previews/confirm']);
    });
  }
}
