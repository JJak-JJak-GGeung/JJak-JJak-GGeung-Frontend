import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'approval.dart';
import 'home.dart';
import 'shared.dart';
import 'start.dart';
import 'transaction.dart';
import 'upload.dart';

export 'shared.dart' show accessToken, demo;

/// Entry widget for the owner's settlement flow. The server owner mounts this
/// from `main.dart`; screens read the API through `backend` in shared.dart.
///
/// Routes
/// - `/` 점포·거래처·기간 선택
/// - `/period/:p` SCR-01 정산 홈
/// - `/period/:p/transaction/:t` SCR-06 확인 카드 (+ 답변 저장 전 확인)
/// - `/period/:p/upload` 자료 올리기 · 수령 연결 · 대체 확인
/// - `/period/:p/approve` SCR-07 정산표 승인
/// - `/period/:p/approvals` 승인 내역
/// - `/approval/:s` 승인본 상세
class SettlementApp extends StatelessWidget {
  const SettlementApp({super.key});

  static final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const StartScreen(), routes: [
      GoRoute(
          path: 'period/:p',
          builder: (_, s) => HomeScreen(s.pathParameters['p']!),
          routes: [
            GoRoute(
                path: 'transaction/:t',
                builder: (_, s) => TransactionScreen(
                    s.pathParameters['p']!, s.pathParameters['t']!)),
            GoRoute(
                path: 'upload',
                builder: (_, s) => UploadScreen(s.pathParameters['p']!, initialDocument: s.uri.queryParameters['document'])),
            GoRoute(
                path: 'approve',
                builder: (_, s) => ApproveScreen(s.pathParameters['p']!)),
            GoRoute(
                path: 'approvals',
                builder: (_, s) => ApprovalsScreen(s.pathParameters['p']!)),
          ]),
      GoRoute(
          path: 'approval/:s',
          builder: (_, s) => ApprovalDetailScreen(s.pathParameters['s']!)),
    ]),
  ]);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: '짝짜꿍',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: appTheme(),
      );
}
