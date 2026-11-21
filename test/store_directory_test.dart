import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/api.dart';
import 'package:jjakjjakggeung/features/ui/directory.dart';

class DirectoryApi extends Fake implements Backend {
  final calls = <String>[];
  @override
  Future<Json> post(String path, Json body) async {
    calls.add('$path ${body['name']}');
    return {'id': 'new', 'name': body['name'], 'created': true};
  }
}

void main() {
  for (final supplier in [false, true]) {
    testWidgets('수동 등록, 취소 및 반환 supplier=$supplier', (tester) async {
      final api = DirectoryApi();
      Json? saved;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (ctx) => Scaffold(
                    body: TextButton(
                        child: const Text('열기'),
                        onPressed: () async {
                          saved = await showDialog<Json>(
                              context: ctx,
                              builder: (_) => RegisterNameDialog(
                                  api: api,
                                  store: supplier
                                      ? {'id': 's1', 'name': '점포'}
                                      : null));
                        }),
                  ))));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), ' 이름 ');
      await tester.pump();
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      expect(api.calls,
          [supplier ? '/api/stores/s1/suppliers 이름' : '/api/stores 이름']);
      expect(saved?['name'], '이름');
    });
  }
}
