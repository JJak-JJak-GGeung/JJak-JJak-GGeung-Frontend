import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_session_native.dart'
    if (dart.library.js_interop) 'browser_session_web.dart';
import 'features/ui/settlement_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!demo) {
    try {
      final credential = await browserSession();
      accessToken = () => credential;
    } catch (_) {
      runApp(const MaterialApp(
          home: Scaffold(
              body: Center(
        child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                '이 브라우저에 자료를 다시 열 수 있는 정보를 저장할 수 없어요. 사이트 데이터 저장을 허용하고 새로고침해 주세요.')),
      ))));
      return;
    }
  }
  runApp(const ProviderScope(child: SettlementApp()));
}
