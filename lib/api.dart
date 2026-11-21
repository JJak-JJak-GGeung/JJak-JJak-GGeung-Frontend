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

class ApiError implements Exception {
  const ApiError(this.status);
  final int status;
  @override
  String toString() => switch (status) {
        401 => '다시 로그인해 주세요.',
        403 => '이 자료를 열 권한이 없습니다.',
        409 => '자료가 변경되었습니다. 최신 근거를 확인한 뒤 다시 시도하세요.',
        422 => '확인할 자료가 남아 있습니다. 입력과 근거를 확인하세요.',
        _ => '요청을 완료하지 못했습니다 ($status).',
      };
}

class SettlementApi {
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
      throw ApiError(response.statusCode);
    }
    return response;
  }

  dynamic _decode(http.Response response) =>
      jsonDecode(utf8.decode(_checked(response).bodyBytes));

  Future<dynamic> get(String path) async =>
      _decode(await http.get(_url(path), headers: _headers));

  Future<Uint8List> original(String id) async => _checked(await http
          .get(_url('/api/documents/${part(id)}/original'), headers: _headers))
      .bodyBytes;

  Future<Json> post(String path, Json body) async =>
      object(_decode(await http.post(
        _url(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )));

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
