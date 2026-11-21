import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jjakjjakggeung/features/ui/start_button.dart';

void main() {
  testWidgets('처음으로는 정산 기간에서 첫 화면으로 이동한다', (tester) async {
    final router = GoRouter(initialLocation: '/period/a', routes: [
      GoRoute(
          path: '/', builder: (_, __) => const Scaffold(body: Text('점포 선택'))),
      GoRoute(
          path: '/period/:id',
          builder: (_, __) => const Scaffold(body: StartButton())),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('처음으로'));
    await tester.pumpAndSettle();
    expect(find.text('점포 선택'), findsOneWidget);
  });

  testWidgets('검수 초안은 취소하면 유지하고 이동을 확인하면 홈 경로를 돌려준다', (tester) async {
    String? route;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('검수'),
                      onPressed: () async {
                        route = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const Scaffold(
                                    body: StartButton(
                                        returnRoute: true, draft: true))));
                      }),
                ))));
    await tester.tap(find.text('검수'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('처음으로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계속 확인'));
    await tester.pumpAndSettle();
    expect(route, isNull);
    await tester.tap(find.byTooltip('처음으로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처음으로 이동'));
    await tester.pumpAndSettle();
    expect(route, '/');
  });
}
