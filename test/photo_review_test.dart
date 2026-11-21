import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/api.dart';
import 'package:jjakjjakggeung/features/ui/photo_review.dart';

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
      return Future.value({'document_id': 'document-1'});
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
      expect(find.text('원본 보기'), findsOneWidget);
      expect(find.byType(Image), wide ? findsOneWidget : findsNothing);
      await tester.tap(find.text('원본 보기'));
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
          'doc_type': 'DELIVERY',
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
      expect(find.textContaining('샘플'), findsOneWidget);
      final qty = find.widgetWithText(TextFormField, '수량');
      await tester.ensureVisible(qty);
      await tester.enterText(qty, '5');
      await tester.tap(find.text('원본 보기'));
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
      'draft': {
        'supplier_name_read': '샘플',
        'doc_type': 'DELIVERY',
        'doc_date': '2026-01-02',
        'lines': [
          {'item': '채소', 'qty_read': '4', 'unit': 'kg'}
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
    final qty = find.widgetWithText(TextFormField, '수량');
    await tester.ensureVisible(qty);
    await tester.enterText(qty, '3');
    final save = find.text('판독값 확인하고 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final confirmed = jsonDecode(api.confirmed['review_json']!);
    expect(confirmed['lines'][0]['qty_read'], '3');
    expect(confirmed['supplier_id'], 'supplier');
    expect(destination, '/period/period/upload?document=document-1');
    expect(api.uploads, ['/api/photo-previews', '/api/photo-previews/confirm']);
  });
}
