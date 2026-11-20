import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> openSupportUrl(Uri uri) async {
  // Encode spaces as %20 for the app URI. Uri.queryParameters uses "+".
  final phone = Uri.encodeQueryComponent(uri.pathSegments.single);
  final message = Uri.encodeComponent(uri.queryParameters['text']!);
  final app = Uri.parse('whatsapp://send?phone=$phone&text=$message');
  try {
    if (await launchUrl(app, mode: LaunchMode.externalApplication)) return true;
  } on PlatformException {
    // The OS can throw when no installed app handles the WhatsApp URI.
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
