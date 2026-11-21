import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jjakjjakggeung/features/ui/home.dart';
import 'package:jjakjjakggeung/features/ui/shared.dart';

void main() {
  testWidgets('정산 홈은 청구 확인 사유를 한 번만 안내하고 내부 코드를 숨긴다', (tester) async {
    const codes = [
      'INVOICE_PERIOD_UNCONFIRMED', 'MISSING_BILLED_AMOUNT', 'MISSING_EFFECTIVE_INVOICE',
      'NEW_SERVER_REASON', 'ANOTHER_NEW_REASON', 'QTY_MISMATCH',
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settlementProvider('week').overrideWith((ref) async => {'blockers': codes}),
        approvalsProvider('week').overrideWith((ref) async => []),
      ],
      child: MaterialApp(theme: appTheme(), home: const HomeScreen('week')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(keepWords('승인 전에 확인할 것')), 120);
    expect(find.text('이번 주 청구서를 올리거나, 올린 청구서의 기간과 금액을 확인해 주세요.'), findsOneWidget);
    expect(find.text('정산 자료를 다시 확인해 주세요'), findsOneWidget);
    expect(find.text('청구와 수령 수량이 다릅니다'), findsOneWidget);
    for (final code in codes) {
      expect(find.textContaining(code), findsNothing);
    }
    // Let the home screen's pending timers finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  });

  test('청구액만 누락되면 그 항목을 안내한다', () {
    expect(approvalReasons(['MISSING_BILLED_AMOUNT']), ['청구서의 금액을 확인해 주세요']);
    expect(approvalReasons([]), isEmpty);
  });

}
