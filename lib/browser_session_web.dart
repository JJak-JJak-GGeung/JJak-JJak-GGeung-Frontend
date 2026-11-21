import 'dart:js_interop';

@JS('jjakBrowserSession')
external JSPromise<JSString> _session();

Future<String> browserSession() async => (await _session().toDart).toDart;
