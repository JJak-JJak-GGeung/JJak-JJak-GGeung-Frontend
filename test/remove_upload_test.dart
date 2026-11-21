import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jjakjjakggeung/features/ui/shared.dart';
import 'package:jjakjjakggeung/features/ui/upload.dart';

void main() {
  testWidgets('거래일과 정산 기간을 각각 표시하고 삭제를 확인한 뒤 목록 갱신', (tester) async {
    // The connected route and the same client call used in the release app.
    var removed = false;
    var posts = 0;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/periods/test-period/documents/doc/remove');
      posts++;
      removed = true;
      return http.Response(jsonEncode({'removed': true}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            settlementProvider('test-period').overrideWith((ref) async => {
                  'period_start': '2026-11-09',
                  'period_end': '2026-11-15',
                  'items': [],
                  'documents': [
                    if (!removed)
                      {
                        'document_id': 'doc',
                        'doc_type': 'DELIVERY',
                        'source_mode': 'FILE',
                        'filename': 'sample.png',
                        'trade_date': '2025-01-31',
                        'lines': [],
                        'extraction_status': 'COMPLETED'
                      }
                  ],
                }),
          ],
          child: const MaterialApp(
              home: UploadScreen('test-period', initialDocument: 'doc'))));
      await tester.pumpAndSettle();
      expect(find.text('거래일 · 2025-01-31'), findsOneWidget);
      expect(find.textContaining('11/09~11/15'), findsOneWidget);
      final remove = find.text('자료 삭제');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('거래일 · 2025-01-31'), findsNothing);
    }, () => client);
  }, skip: demo);
}
