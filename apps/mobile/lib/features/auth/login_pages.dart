import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sobatnira_ui.dart';

class LoginWelcomePage extends StatelessWidget {
  const LoginWelcomePage({required this.onContinue, super.key});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    children: [
      const _LoginLogo(width: 290),
      const SizedBox(height: NiraSpace.xl),
      Semantics(
        header: true,
        child: Text(
          'SobatNira',
          textAlign: TextAlign.center,
          style: niraText(NiraType.title, weight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: NiraSpace.xl),
      NiraButton('Masuk', onContinue, shadow: false),
    ],
  );
}

class LoginFormPage extends StatefulWidget {
  const LoginFormPage({
    required this.onSubmit,
    required this.onBack,
    this.busy = false,
    this.message,
    super.key,
  });

  final void Function(String email, String password) onSubmit;
  final VoidCallback onBack;
  final bool busy;
  final String? message;

  @override
  State<LoginFormPage> createState() => _LoginFormPageState();
}

class _LoginFormPageState extends State<LoginFormPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String? _emailError(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Masukkan email.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Masukkan email dengan format yang benar.';
    }
    return null;
  }

  void _submit() {
    if (widget.busy) return;
    setState(() {
      _submitted = true;
      _passwordVisible = false;
    });
    if (!_form.currentState!.validate()) {
      final focus = _emailError(_email.text) != null
          ? _emailFocus
          : _passwordFocus;
      focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onSubmit(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !widget.busy) widget.onBack();
    },
    child: _LoginScaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.busy ? null : widget.onBack,
          tooltip: 'Kembali',
          icon: const BackButtonIcon(),
        ),
      ),
      children: [
        const _LoginLogo(width: 200),
        const SizedBox(height: NiraSpace.xl),
        Semantics(
          header: true,
          child: Text(
            'Masuk ke SobatNira',
            style: niraText(NiraType.title, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: NiraSpace.xl),
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Form(
            key: _form,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  focusNode: _emailFocus,
                  readOnly: widget.busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: _emailError,
                  errorBuilder: _fieldError,
                  decoration: _decoration('Email'),
                ),
                const SizedBox(height: NiraSpace.lg),
                TextFormField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  readOnly: widget.busy,
                  obscureText: !_passwordVisible,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      (value ?? '').isEmpty ? 'Masukkan kata sandi.' : null,
                  errorBuilder: _fieldError,
                  decoration: _decoration(
                    'Kata sandi',
                  ).copyWith(suffixIcon: _passwordToggle()),
                ),
              ],
            ),
          ),
        ),
        if (widget.message case final String message) ...[
          const SizedBox(height: NiraSpace.md),
          Semantics(liveRegion: true, child: Text(message)),
        ],
        const SizedBox(height: NiraSpace.xl),
        Semantics(
          liveRegion: widget.busy,
          child: NiraButton(
            widget.busy ? 'Memeriksa akun…' : 'Masuk',
            widget.busy ? null : _submit,
            shadow: false,
          ),
        ),
      ],
    ),
  );

  Widget _passwordToggle() {
    final label = _passwordVisible
        ? 'Sembunyikan kata sandi'
        : 'Tampilkan kata sandi';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconButton(
        onPressed: widget.busy
            ? null
            : () => setState(() => _passwordVisible = !_passwordVisible),
        icon: Icon(
          _passwordVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          semanticLabel: label,
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    floatingLabelStyle: niraText(NiraType.section, color: niraLeaf),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(niraRadius),
      borderSide: const BorderSide(color: niraLeaf),
    ),
  );

  Widget _fieldError(BuildContext context, String message) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: niraText(
        NiraType.caption,
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}

class _LoginScaffold extends StatelessWidget {
  const _LoginScaffold({required this.children, this.appBar});

  final PreferredSizeWidget? appBar;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: niraPageInset(context),
                      vertical: NiraSpace.xl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoginLogo extends StatelessWidget {
  const _LoginLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Center(
    child: Image.asset(
      'assets/sobatnira/art/ukaisya-logo.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'Ukaisya, PT Tiga Dewi Timur Raya',
    ),
  );
}
