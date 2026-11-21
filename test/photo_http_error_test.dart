import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jjakjjakggeung/api.dart';

void main() {
  final api = SettlementApi('https://example.test', () => null);
  Future<void> check(
    String path,
    int status,
    String detail,
    String expected,
  ) async {
    await http.runWithClient(
      () async {
        await expectLater(
          api.upload(path, Uint8List(1), 'test.png', 'image/png'),
          throwsA(isA<ApiError>().having((e) => e.detail, 'detail', expected)),
        );
      },
      () => MockClient(
        (request) async =>
            http.Response(jsonEncode({'detail': detail}), status),
      ),
    );
  }

  test('preview and confirm distinguish an unavailable route from a missing record', () async {
    for (final path in ['/api/photo-previews', '/api/photo-previews/confirm']) {
      await check(path, 404, 'Not Found', 'PHOTO_API_UNAVAILABLE');
      await check(path, 405, 'Method Not Allowed', 'PHOTO_API_UNAVAILABLE');
      await check(path, 404, 'STORE_NOT_FOUND', 'STORE_NOT_FOUND');
      await check(path, 503, 'PHOTO_READING_FAILED', 'PHOTO_READING_FAILED');
    }
    await check('/api/periods/p/documents', 404, 'Not Found', 'Not Found');
  });
}
