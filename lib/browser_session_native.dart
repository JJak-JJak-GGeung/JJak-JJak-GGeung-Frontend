import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

Future<String> browserSession() async {
  final store = SharedPreferencesAsync();
  const key = 'jjak.browserSession.v1';
  final saved = await store.getString(key);
  if (saved != null) return saved;
  final credential = 'device-v1.${requestKey()}${requestKey()}';
  await store.setString(key, credential);
  return credential;
}
