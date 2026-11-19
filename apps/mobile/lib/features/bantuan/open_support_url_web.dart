import 'package:web/web.dart' as web;

Future<bool> openSupportUrl(Uri uri) {
  // Same-tab navigation needs neither a popup nor Flutter plugin registration.
  web.window.location.assign(uri.toString());
  return Future.value(true);
}
