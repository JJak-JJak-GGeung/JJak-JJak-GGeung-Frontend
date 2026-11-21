import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

typedef Json = Map<String, dynamic>;

Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

List<Json> objects(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : [];

final _random = Random.secure();
String requestKey() => List.generate(
    16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Error returned by the settlement server. [detail] carries the server's
/// reason code when it sent one (STALE_REVISION, BLOCKED, KEY_REUSE ...).
class ApiError implements Exception {
  const ApiError(this.status, [this.detail]);
  final int status;
  final String? detail;

  bool get stale => status == 409 && detail != 'KEY_REUSE';

  @override
  String toString() => switch (status) {
        401 => '다시 로그인해 주세요.',
        403 => '이 자료를 열 권한이 없습니다.',
        404 => '자료를 찾지 못했습니다.',
        409 when detail == 'KEY_REUSE' =>
          '같은 요청 번호로 다른 내용이 전송되었습니다. 화면을 새로 열어 다시 시도하세요.',
        409 => '자료가 변경되었습니다. 최신 근거를 확인한 뒤 다시 시도하세요.',
        413 => '파일은 10MB 이하만 올릴 수 있습니다.',
        415 => 'PNG·JPEG·WebP 사진만 올릴 수 있습니다.',
        422 => '확인할 자료가 남아 있습니다. 입력과 근거를 확인하세요.',
        503 => '원본 저장소에 연결하지 못했습니다. 잠시 뒤 다시 시도하세요.',
        _ => '요청을 완료하지 못했습니다 ($status).',
      };
}

/// What the screens need from a server. [SettlementApi] talks to the real
/// FastAPI server; the demo backend answers the same paths from memory.
abstract class Backend {
  Future<dynamic> get(String path);
  Future<Json> post(String path, Json body);
  Future<Json> upload(String path, Uint8List bytes, String name, String mime,
      [Map<String, String> fields = const {}]);
  Future<Uint8List> original(String documentId);
}

class SettlementApi implements Backend {
  SettlementApi(this.base, this.token);
  final String base;
  final String? Function() token;

  Uri _url(String path) =>
      Uri.parse('${base.replaceFirst(RegExp(r"/+$"), "")}$path');

  Map<String, String> get _headers {
    final accessToken = token();
    return {if (accessToken != null) 'Authorization': 'Bearer $accessToken'};
  }

  http.Response _checked(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? detail;
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final value = body is Map ? body['detail'] : null;
        detail = value is Map
            ? (value['code'] ?? value['error'])?.toString()
            : value?.toString();
      } catch (_) {}
      throw ApiError(response.statusCode, detail);
    }
    return response;
  }

  dynamic _decode(http.Response response) =>
      jsonDecode(utf8.decode(_checked(response).bodyBytes));

  @override
  Future<dynamic> get(String path) async =>
      _decode(await http.get(_url(path), headers: _headers));

  @override
  Future<Uint8List> original(String id) async => _checked(await http
          .get(_url('/api/documents/${part(id)}/original'), headers: _headers))
      .bodyBytes;

  @override
  Future<Json> post(String path, Json body) async =>
      object(_decode(await http.post(
        _url(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )));

  @override
  Future<Json> upload(String path, Uint8List bytes, String name, String mime,
      [Map<String, String> fields = const {}]) async {
    final request = http.MultipartRequest('POST', _url(path))
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: name, contentType: MediaType.parse(mime)));
    return object(
        _decode(await http.Response.fromStream(await request.send())));
  }
}

String part(Object? value) => Uri.encodeComponent(value?.toString() ?? '');

List<Json> records(dynamic response, String key) =>
    objects(response is List ? response : object(response)[key]);
