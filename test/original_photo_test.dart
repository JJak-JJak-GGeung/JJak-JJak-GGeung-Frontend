import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/features/ui/original_photo.dart';

void main() {
  // A blank 200 x 100 PNG. Neither a customer image nor OCR is needed.
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAIAAABM5OhcAAAAyElEQVR42u3SMREAAAjEMMC/58cEA0MioddOUnBtJMBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWGAsjIWxwFgYC2OBsTAWxgJjYSyMBcbCWBgLjIWxMBYYC2NhLDAWxsJYYCyMhbHAWBgLY4GxMBbGAmNhLIwFxsJYGAuMhbEwFhgLY2EsMBbGwlhgLIyFscBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWxgJjYSyMBcbCWBgLjIWxMBYYi98WU5QDxbEy+mYAAAAASUVORK5CYII=');
  Future<void> show(
      WidgetTester tester, Map<String, dynamic> location, Size viewport) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox.fromSize(
                    size: viewport,
                    child: OriginalPhoto(bytes: bytes, location: location))))));
    final photo = find.byType(RawImage);
    for (var attempt = 0; attempt < 60 && photo.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(photo, findsOneWidget);
  }

  for (final viewport in [const Size(300, 400), const Size(600, 150)]) {
    testWidgets('각 행을 이미지의 실제 픽셀에 맞게 표시한다 - $viewport', (tester) async {
      for (final y in [18, 60]) {
        await show(
            tester,
            {
              'row': y == 18 ? 1 : 2,
              'region': [10, y, 190, y + 12]
            },
            viewport);
        final photo = tester.getRect(find.byType(RawImage));
        final marked = find.bySemanticsLabel('선택한 원본 위치');
        final expected = Rect.fromLTRB(
            photo.left + photo.width * .05,
            photo.top + photo.height * y / 100,
            photo.left + photo.width * .95,
            photo.top + photo.height * (y + 12) / 100);
        expect(tester.getRect(marked), expected);
        expect(
            find.ancestor(of: marked, matching: find.byType(InteractiveViewer)),
            findsOneWidget);
      }
    });
  }
  testWidgets('좌표가 없거나 잘못된 자료와 전체 원본을 구분한다', (tester) async {
    for (final region in [
      null,
      [200, 0, 250, 10],
      [20, 30, 10, 10],
      ['bad', 0, 4, 5]
    ]) {
      await show(tester, {'row': 2, 'region': region}, const Size(300, 400));
      expect(find.text('원본에 표시할 위치 정보가 없습니다.'), findsOneWidget);
      expect(find.bySemanticsLabel('선택한 원본 위치'), findsNothing);
    }
    await show(tester, {}, const Size(300, 400));
    expect(find.bySemanticsLabel('선택한 원본 위치'), findsNothing);
    expect(find.text('원본에 표시할 위치 정보가 없습니다.'), findsNothing);
  });
}
