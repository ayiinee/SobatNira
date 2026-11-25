import 'package:web/web.dart' as web;

String? takeAdminInvitation() {
  final current = Uri.base;
  if (current.queryParameters['acceptInvite'] != '1') return null;
  final clean = current.replace(query: '', fragment: '');
  web.window.history.replaceState(null, '', clean.path);
  try {
    final params = Uri.splitQueryString(current.fragment);
    final token = params['access_token'];
    return params['type'] == 'invite' &&
            token != null &&
            token.isNotEmpty &&
            token.length <= 8192
        ? token
        : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
