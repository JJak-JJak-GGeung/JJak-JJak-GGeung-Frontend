import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<String> recordingPath(String filename) async => filename;

Future<({Uint8List bytes, String mime})> readRecording(String path) async {
  final response = await http.get(Uri.parse(path));
  if (response.statusCode != 200) {
    throw StateError('녹음 파일 읽기 실패');
  }
  return (
    bytes: response.bodyBytes,
    mime: response.headers['content-type']?.split(';').first ?? 'audio/webm',
  );
}
