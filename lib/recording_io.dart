import 'dart:io';
import 'dart:typed_data';

Future<String> recordingPath(String filename) async {
  final directory = await Directory.systemTemp.createTemp('jjak-recording-');
  return '${directory.path}/$filename';
}

Future<({Uint8List bytes, String mime})> readRecording(String path) async {
  final file = File(path);
  try {
    return (bytes: await file.readAsBytes(), mime: 'audio/wav');
  } finally {
    if (await file.exists()) await file.delete();
    await file.parent.delete();
  }
}
