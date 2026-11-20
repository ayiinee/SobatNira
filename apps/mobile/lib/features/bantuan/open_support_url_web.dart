import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

Future<bool> openSupportUrl(Uri uri) {
  final target = switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => uri,
    _ => Uri.https('web.whatsapp.com', '/send', {
      'phone': uri.pathSegments.single,
      'text': uri.queryParameters['text']!,
    }),
  };
  // Same-tab navigation needs neither a popup nor Flutter plugin registration.
  web.window.location.assign(target.toString());
  return Future.value(true);
}
