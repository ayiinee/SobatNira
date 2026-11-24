import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<bool> saveReportFile(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('Penyimpanan tersedia di Android dan browser.');
  }
  return await const MethodChannel('sobatnira/report-file').invokeMethod<bool>(
        'save',
        {'bytes': bytes, 'filename': filename, 'mime': mime},
      ) ??
      false;
}
