import 'package:flutter/material.dart';

import 'features/beranda/home_page.dart';
import 'features/kloter/connected_kloter_page.dart';
import 'features/pekerjaan/review_api.dart';
import 'sobatnira_ui.dart';

void main() => runApp(const SobatNiraApp());

class SobatNiraApp extends StatelessWidget {
  const SobatNiraApp({
    super.key,
    this.connected = connectedMobile,
    this.signIn = ReviewApi.signIn,
    this.configurationErrors,
  });

  final bool connected;
  final Future<ReviewApi> Function(String email, String password) signIn;
  final List<String>? configurationErrors;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SobatNira',
    debugShowCheckedModeBanner: false,
    theme: niraTheme(),
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFF2F2EE),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child,
        ),
      ),
    ),
    home: connected
        ? ConnectedKloterPage(
            invalidConfiguration:
                configurationErrors ?? ReviewApi.invalidConfiguration,
            signIn: signIn,
          )
        : const NiraHome(),
  );
}
