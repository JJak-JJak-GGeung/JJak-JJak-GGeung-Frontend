import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/ui/settlement_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (demo) {
    runApp(const ProviderScope(child: SettlementApp()));
    return;
  }
  if (url.isEmpty || key.isEmpty) {
    runApp(const _OwnerLogin());
    return;
  }
  await Supabase.initialize(url: url, publishableKey: key);
  final auth = Supabase.instance.client.auth;
  accessToken = () => auth.currentSession?.accessToken;
  runApp(StreamBuilder<AuthState>(
    stream: auth.onAuthStateChange,
    builder: (context, snapshot) {
      final session = auth.currentSession;
      return session == null
          ? _OwnerLogin(auth: auth)
          : ProviderScope(
              key: ValueKey(session.user.id), child: const SettlementApp());
    },
  ));
}

class _OwnerLogin extends StatefulWidget {
  const _OwnerLogin({this.auth});
  final GoTrueClient? auth;

  @override
  State<_OwnerLogin> createState() => _OwnerLoginState();
}

class _OwnerLoginState extends State<_OwnerLogin> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy ||
        widget.auth == null ||
        email.text.trim().isEmpty ||
        password.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth!.signInWithPassword(
          email: email.text.trim(), password: password.text);
    } catch (_) {
      if (mounted) setState(() => error = '로그인하지 못했습니다. 계정과 연결을 확인하세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '짝짜꿍',
        home: Scaffold(
          appBar: AppBar(title: const Text('점주 로그인')),
          body: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  if (widget.auth == null)
                    const Text('서버 배포의 점주 로그인 설정을 확인해 주세요.')
                  else ...[
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: '이메일')),
                    TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '비밀번호'),
                        onSubmitted: (_) => login()),
                    if (error != null) Text(error!),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: busy ? null : login,
                        child: const Text('로그인')),
                  ],
                ]),
          )),
        ),
      );
}
