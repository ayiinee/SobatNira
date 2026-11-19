import 'package:url_launcher/url_launcher.dart';

Future<bool> openSupportUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
