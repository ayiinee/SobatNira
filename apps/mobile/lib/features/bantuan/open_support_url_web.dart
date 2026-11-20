import 'package:web/web.dart' as web;

Future<bool> openSupportUrl(Uri uri) {
  // The universal link works even when a phone requests the desktop site.
  // Same-tab navigation needs neither a popup nor Flutter plugin registration.
  web.window.location.assign(uri.toString());
  return Future.value(true);
}
