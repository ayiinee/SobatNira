import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveReportFile(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  try {
    web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..click();
  } finally {
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  }
  return true;
}
