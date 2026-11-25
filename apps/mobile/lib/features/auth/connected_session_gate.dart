import 'dart:async';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/nira_loading.dart';
import '../../widgets/page_frame.dart';
import 'login_pages.dart';
import 'admin_invitation_page.dart';
import 'admin_invitation_stub.dart'
    if (dart.library.js_interop) 'admin_invitation_web.dart';
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
  String? _invitationToken;

  @override
  void initState() {
    super.initState();
    _invitationToken = takeAdminInvitation();
  }

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
      if (_invitationToken case final token?) {
        return AdminInvitationPage(
          token: token,
          onDone: () => setState(() {
            _invitationToken = null;
            _showLogin = true;
            _loginMessage =
                'Kata sandi tersimpan. Masuk dengan akun admin Anda.';
          }),
        );
      }
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
    return NiraLoading(
      busy: _checkingAccess,
      finish: _scope != null,
      label: 'Memeriksa akses pabrik…',
      loadingBuilder: (_, indicator) => _centerAccess(indicator),
      child: _authenticated(api),
    );
  }

  Widget _authenticated(ReviewApi api) {
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
    if (_factories == null) return _accessPending(api);
    return NiraPageScaffold(
      title: const Text('Akses pabrik'),
      actions: [
        TextButton(onPressed: _endSession, child: const Text('Keluar')),
      ],
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NiraSpace.lg),
          children: _noAccess(),
        ),
      ),
    );
  }

  Widget _centerAccess(Widget body) => Scaffold(
    backgroundColor: niraPaper,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: niraMaxContentWidth),
          child: body,
        ),
      ),
    ),
  );

  Widget _accessPending(ReviewApi api) => _centerAccess(
    SingleChildScrollView(
      padding: const EdgeInsets.all(NiraSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: const Text(
              'Akses pabrik belum dapat diperiksa. Periksa koneksi dan coba lagi.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: NiraSpace.lg),
          NiraButton('Coba lagi', () => _checkAccess(api), shadow: false),
        ],
      ),
    ),
  );

  List<Widget> _noAccess() => [
    Semantics(
      liveRegion: true,
      child: const Text('Akun ini belum memiliki akses pabrik aktif.'),
    ),
    const SizedBox(height: NiraSpace.sm),
    const Text('Hubungi pengelola pabrik untuk mendapatkan akses.'),
  ];
}
