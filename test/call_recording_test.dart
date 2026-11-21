import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/api.dart';
import 'package:jjakjjakggeung/features/ui/call_recording.dart';

class CallBackend implements Backend {
  CallBackend({this.fail});
  final ApiError? fail;
  final uploads = <(String, String)>[];
  final posts = <(String, Json)>[];

  @override
  Future<Json> upload(
    String path,
    Uint8List bytes,
    String name,
    String mime, [
    Map<String, String> fields = const {},
  ]) async {
    uploads.add((path, mime));
    if (fail != null) throw fail!;
    return {'draft_text': '거래처는 장어 40킬로를 다 보냈다고 합니다.'};
  }

  @override
  Future<dynamic> get(String path) async => switch (path) {
    '/api/stores' => {
      'stores': [
        {'id': 'store', 'name': '점포'},
      ],
    },
    '/api/suppliers?store_id=store' => {
      'suppliers': [
        {'id': 'supplier', 'name': '거래처'},
      ],
    },
    '/api/periods?store_id=store&supplier_id=supplier' => {
      'periods': [
        {
          'period_id': 'period',
          'period_start': '2026-11-09',
          'period_end': '2026-11-15',
        },
      ],
    },
    '/api/periods/period' => {
      'input_revision': 7,
      'items': [
        {
          'transaction_id': 'tx',
          'delivery_date': '2026-11-13',
          'item': '손질 장어',
          'billed_qty': '40',
          'unit': 'kg',
        },
      ],
    },
    _ => throw const ApiError(404),
  };

  @override
  Future<Json> post(String path, Json body) async {
    posts.add((path, body));
    return {'memo_id': 'memo', 'input_revision': 8};
  }

  @override
  Future<Uint8List> original(String documentId) => throw UnimplementedError();
}

/// Opens the review page and returns a getter for the route it pops with.
Future<String? Function()> open(WidgetTester tester, CallBackend api) async {
  String? destination;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                destination = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => CallRecordingReview(
                      PlatformFile(
                        name: 'call.m4a',
                        bytes: Uint8List(2048),
                        size: 2048,
                      ),
                      api: api,
                    ),
                  ),
                );
              },
              child: const Text('녹음 선택'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('녹음 선택'));
  await tester.pumpAndSettle();
  return () => destination;
}

void main() {
  testWidgets('통화녹음을 받아써서 고친 뒤 거래 메모로 저장한다', (tester) async {
    final api = CallBackend();
    final destination = await open(tester, api);

    expect(api.uploads, [('/api/transcriptions', 'audio/x-m4a')]);
    final memo = find.widgetWithText(TextField, '통화 메모');
    expect(find.text('거래처는 장어 40킬로를 다 보냈다고 합니다.'), findsOneWidget);
    // One store, supplier, period and item: all chosen without a tap.
    expect(find.textContaining('손질 장어'), findsOneWidget);

    await tester.enterText(memo, '거래처는 40킬로, 가게 기록은 36킬로입니다.');
    final save = find.text('통화 메모 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.posts.single.$1, '/api/transactions/tx/memos');
    final body = api.posts.single.$2;
    expect(body['confirmed_text'], '거래처는 40킬로, 가게 기록은 36킬로입니다.');
    expect(body['source_mode'], 'VOICE_MEMO');
    expect(body['expected_revision'], 7);
    expect(body['request_key'], isNotEmpty);
    expect(destination(), '/period/period/transaction/tx');
  });

  testWidgets('받아쓰기에 실패하면 직접 입력해 저장할 수 있다', (tester) async {
    final api = CallBackend(fail: const ApiError(415, 'UNSUPPORTED_AUDIO'));
    await open(tester, api);

    expect(find.textContaining('지원하지 않는 녹음 형식입니다.'), findsOneWidget);
    expect(find.text('다시 받아쓰기'), findsOneWidget);
    final save = find.text('통화 메모 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('저장할 통화 내용을 입력하세요.'), findsOneWidget);
    expect(api.posts, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, '통화 메모'),
      '직접 적은 통화 내용',
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.posts.single.$2['confirmed_text'], '직접 적은 통화 내용');
  });

  test('녹음 파일 확장자를 서버가 아는 MIME으로 보낸다', () {
    expect(callMime('M4A'), 'audio/x-m4a');
    expect(callMime('mp3'), 'audio/mpeg');
    expect(callMime('amr'), 'application/octet-stream');
  });
}
