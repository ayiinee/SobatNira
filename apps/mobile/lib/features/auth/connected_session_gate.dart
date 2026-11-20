import 'dart:async';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import 'login_pages.dart';
import '../pekerjaan/review_api.dart';

typedef FactoryHomeBuilder =
    Widget Function(
      ReviewApi api,
      List<FactoryScope> factories,
      FactoryScope scope,
      ValueChanged<FactoryScope> selectFactory,
      VoidCallback signOut,
      bool synthetic,
      ValueChanged<bool> onSyntheticChanged,
    );

class ConnectedSessionGate extends StatefulWidget {
  const ConnectedSessionGate({
    super.key,
    this.signIn = ReviewApi.signIn,
    this.invalidConfiguration = const [],
    required this.homeBuilder,
  });
  final Future<ReviewApi> Function(String email, String password) signIn;
  final List<String> invalidConfiguration;
  final FactoryHomeBuilder homeBuilder;

  @override
  State<ConnectedSessionGate> createState() => _ConnectedSessionGateState();
}

class _ConnectedSessionGateState extends State<ConnectedSessionGate> {
  final _syntheticTenants = <String>{};
  ReviewApi? _api;
  List<FactoryScope>? _factories;
  FactoryScope? _scope;
  bool _showLogin = false;
  bool _signingIn = false;
  bool _checkingAccess = false;
  String? _loginMessage;

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _signIn(String email, String password) async {
    if (_signingIn || _api != null) return;
    setState(() {
      _signingIn = true;
      _loginMessage = null;
    });
    try {
      final api = await widget.signIn(email, password);
      if (!mounted) {
        api.close();
        return;
      }
      api.onSessionExpired = () => scheduleMicrotask(() {
        if (mounted && identical(_api, api)) _endSession(expired: true);
      });
      _api = api;
      unawaited(_checkAccess(api));
    } catch (error) {
      if (mounted) {
        setState(() {
          _loginMessage = switch (error) {
            ReviewApiError(status: 429) =>
              'Terlalu banyak percobaan. Tunggu sebentar sebelum mencoba lagi.',
            ReviewApiError(authCode: 'invalid_credentials') =>
              'Email atau kata sandi tidak cocok.',
            ReviewApiError(authCode: 'email_not_confirmed') =>
              'Email belum dikonfirmasi. Periksa kotak masuk atau hubungi pengelola pabrik.',
            ReviewApiError(authCode: 'user_banned') =>
              'Akun ini tidak bisa digunakan. Hubungi pengelola pabrik.',
            ReviewApiError(status: >= 500) || TimeoutException() =>
              'Belum bisa masuk. Periksa koneksi dan coba lagi.',
            _ => 'Belum bisa masuk. Coba lagi atau hubungi pengelola pabrik.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _checkAccess(ReviewApi api) async {
    if (_checkingAccess) return;
    setState(() => _checkingAccess = true);
    try {
      final factories = await api.factories();
      if (!mounted || !identical(_api, api)) return;
      setState(() {
        if (_factories == null) {
          _syntheticTenants.addAll(
            factories
                .where((scope) => scope.tenantName == 'SobatNira Uji')
                .map((scope) => scope.tenantId),
          );
        }
        _factories = factories;
        _scope = factories.firstOrNull;
      });
    } catch (_) {
      // A transient failure leaves access unloaded so the user can retry.
      // ReviewApi handles expired sessions before returning a 401 error.
    } finally {
      if (mounted && identical(_api, api)) {
        setState(() => _checkingAccess = false);
      }
    }
  }

  void _endSession({bool expired = false}) {
    _syntheticTenants.clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
    _api?.close();
    setState(() {
      _api = null;
      _factories = null;
      _scope = null;
      _checkingAccess = false;
      _showLogin = true;
      _loginMessage = expired ? 'Sesi berakhir. Masuk kembali.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    if (widget.invalidConfiguration.isNotEmpty) {
      return NiraPageScaffold(
        title: const Text('SobatNira'),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(NiraSpace.lg),
            children: [
              const Text('Layanan masuk belum dikonfigurasi.'),
              const Text('Hubungi pengelola SobatNira untuk bantuan.'),
              Text('Periksa ${widget.invalidConfiguration.join(', ')}.'),
            ],
          ),
        ),
      );
    }
    if (api == null) {
      return _showLogin
          ? LoginFormPage(
              busy: _signingIn,
              message: _loginMessage,
              onSubmit: _signIn,
              onBack: () => setState(() {
                _showLogin = false;
                _loginMessage = null;
              }),
            )
          : LoginWelcomePage(
              onContinue: () => setState(() => _showLogin = true),
            );
    }
    final scope = _scope;
    if (scope != null) {
      void selectFactory(FactoryScope selected) {
        if (selected != _scope && _factories!.contains(selected)) {
          setState(() => _scope = selected);
        }
      }

      final synthetic = _syntheticTenants.contains(scope.tenantId);
      void changeSynthetic(bool value) {
        if (value) {
          _syntheticTenants.add(scope.tenantId);
        } else {
          _syntheticTenants.remove(scope.tenantId);
        }
      }

      return widget.homeBuilder(
        api,
        _factories!,
        scope,
        selectFactory,
        _endSession,
        synthetic,
        changeSynthetic,
      );
    }
    return NiraPageScaffold(
      title: const Text('Akses pabrik'),
      actions: [
        TextButton(onPressed: _endSession, child: const Text('Keluar')),
      ],
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NiraSpace.lg),
          children: _factories == null ? _accessPending(api) : _noAccess(),
        ),
      ),
    );
  }

  List<Widget> _accessPending(ReviewApi api) => _checkingAccess
      ? [
          const LinearProgressIndicator(),
          const SizedBox(height: NiraSpace.lg),
          Semantics(
            liveRegion: true,
            child: const Text('Memeriksa akses pabrik…'),
          ),
        ]
      : [
          Semantics(
            liveRegion: true,
            child: const Text(
              'Akses pabrik belum dapat diperiksa. Periksa koneksi dan coba lagi.',
            ),
          ),
          const SizedBox(height: NiraSpace.lg),
          NiraButton('Coba lagi', () => _checkAccess(api), shadow: false),
        ];

  List<Widget> _noAccess() => [
    Semantics(
      liveRegion: true,
      child: const Text('Akun ini belum memiliki akses pabrik aktif.'),
    ),
    const SizedBox(height: NiraSpace.sm),
    const Text('Hubungi pengelola pabrik untuk mendapatkan akses.'),
  ];
}
