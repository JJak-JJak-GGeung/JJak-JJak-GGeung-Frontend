import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jjakjjakggeung/features/ui/period_history.dart';

const _rows = [
  {
    'period_id': 'november',
    'period_start': '2026-11-09',
    'period_end': '2026-11-15',
    'label': '11월 정산',
  },
  {
    'period_id': 'new-year',
    'period_start': '2025-12-29',
    'period_end': '2026-01-04',
    'label': '연말에 걸친 정산',
  },
  {
    'period_id': 'june',
    'period_start': '2024-06-10',
    'period_end': '2024-06-16',
    'label': '6월 정산',
  },
];

Future<void> _openHistory(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: PeriodHistory(rows: _rows)),
        ),
      ),
      GoRoute(
        path: '/period/:id',
        builder: (_, state) => Scaffold(
          body: Text('정산 상세: ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('연도를 선택하면 해당 연도와 겹치는 주를 보여준다', (tester) async {
    await _openHistory(tester);
    expect(find.text('6월 정산'), findsOneWidget);

    await tester.tap(find.text('전체 연도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025년').last);
    await tester.pumpAndSettle();
    expect(find.text('연말에 걸친 정산'), findsOneWidget);
    expect(find.text('11월 정산'), findsNothing);
    expect(find.text('6월 정산'), findsNothing);

    await tester.tap(find.text('2025년'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026년').last);
    await tester.pumpAndSettle();
    expect(find.text('연말에 걸친 정산'), findsOneWidget);
    expect(find.text('11월 정산'), findsOneWidget);
  });

  testWidgets('달력에서 정한 범위의 주를 조회하고 기존 상세를 연다', (tester) async {
    await _openHistory(tester);
    await tester.tap(find.text('달력에서 기간 선택'));
    await tester.pumpAndSettle();

    final picker = find.byType(DateRangePickerDialog);
    final strings = MaterialLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(strings.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    final fields =
        find.descendant(of: picker, matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '01/04/2026');
    await tester.enterText(fields.at(1), '01/04/2026');
    await tester.tap(find.widgetWithText(TextButton, '조회'));
    await tester.pumpAndSettle();

    expect(find.text('2026.1.4 ~ 2026.1.4'), findsOneWidget);
    expect(find.text('연말에 걸친 정산'), findsOneWidget);
    expect(find.text('11월 정산'), findsNothing);
    expect(find.text('6월 정산'), findsNothing);

    await tester.tap(find.text('연말에 걸친 정산'));
    await tester.pumpAndSettle();
    expect(find.text('정산 상세: new-year'), findsOneWidget);
  });
}
