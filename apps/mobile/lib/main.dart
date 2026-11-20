import 'package:flutter/material.dart';

import 'features/auth/connected_session_gate.dart';
import 'features/beranda/home_page.dart';
import 'features/pekerjaan/review_api.dart';
import 'sobatnira_ui.dart';

const _demoMode = String.fromEnvironment('SOBATNIRA_MODE') == 'demo';

void main() => runApp(const SobatNiraApp());

class SobatNiraApp extends StatelessWidget {
  const SobatNiraApp({
    super.key,
    this.connected = !_demoMode,
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
        ? ConnectedSessionGate(
            invalidConfiguration:
                configurationErrors ?? ReviewApi.invalidConfiguration,
            signIn: signIn,
            homeBuilder:
                (
                  api,
                  factories,
                  scope,
                  selectFactory,
                  signOut,
                  synthetic,
                  onSyntheticChanged,
                ) => NiraHome(
                  key: ValueKey((api, scope.tenantId, scope.factoryId)),
                  api: api,
                  factories: factories,
                  scope: scope,
                  selectFactory: selectFactory,
                  signOut: signOut,
                  synthetic: synthetic,
                  onSyntheticChanged: onSyntheticChanged,
                ),
          )
        : const NiraHome(),
  );
}
