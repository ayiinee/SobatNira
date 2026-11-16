import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sobatnira_ui.dart';

const _loginPaper = Color(0xFFFEFCF9);

class LoginWelcomePage extends StatelessWidget {
  const LoginWelcomePage({required this.onContinue, super.key});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    child: SafeArea(
      minimum: const EdgeInsets.fromLTRB(28, 0, 28, 46),
      child: Column(
        children: [
          const Expanded(
            child: Align(
              alignment: Alignment(0, .16),
              child: _LoginLogo(width: 310),
            ),
          ),
          SizedBox(
            height: 66,
            child: NiraButton('Masuk', onContinue, shadow: false),
          ),
        ],
      ),
    ),
  );
}

class LoginFormPage extends StatefulWidget {
  const LoginFormPage({required this.onSubmit, super.key});

  final VoidCallback onSubmit;

  @override
  State<LoginFormPage> createState() => _LoginFormPageState();
}

class _LoginFormPageState extends State<LoginFormPage> {
  final _form = GlobalKey<FormState>();
  bool _rememberMe = false;

  void _submit() {
    if (_form.currentState!.validate()) widget.onSubmit();
  }

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        return SafeArea(
          minimum: EdgeInsets.only(
            top: keyboardVisible ? 16 : constraints.maxHeight * .267,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _LoginLogo(width: 248)),
                  SizedBox(height: keyboardVisible ? 24 : 59),
                  _field(
                    label: 'Nama Pengguna',
                    icon: Icons.person_outline,
                    error: 'Masukkan nama pengguna.',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: 'Kata sandi',
                    icon: Icons.lock_outline,
                    error: 'Masukkan kata sandi.',
                    isPassword: true,
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _rememberControl(),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: niraLeaf,
                          padding: EdgeInsets.zero,
                          textStyle: niraText(13),
                        ),
                        onPressed: () => showUnavailable(context),
                        child: const Text('Lupa kata sandi?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 50,
                    child: NiraButton('Masuk', _submit, shadow: false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _rememberControl() => MergeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: _rememberMe,
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: niraGreen, width: 1.3),
          onChanged: (value) => setState(() => _rememberMe = value ?? false),
        ),
        GestureDetector(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          excludeFromSemantics: true,
          child: Text('Ingat saya', style: niraText(13, color: Colors.black87)),
        ),
      ],
    ),
  );

  Widget _field({
    required String label,
    required IconData icon,
    required String error,
    bool isPassword = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: niraGreen, width: 1.2),
    );
    return TextFormField(
      obscureText: isPassword,
      autocorrect: false,
      enableSuggestions: !isPassword,
      textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: isPassword ? (_) => _submit() : null,
      validator: (value) =>
          value == null || value.trim().isEmpty ? error : null,
      style: niraText(13),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: niraText(13, color: niraLeaf),
        prefixIcon: Icon(icon, size: 19, color: niraMuted),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 50,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: niraGreen, width: 2),
        ),
        border: border,
      ),
    );
  }
}

class _LoginScaffold extends StatelessWidget {
  const _LoginScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(backgroundColor: _loginPaper, body: child),
  );
}

class _LoginLogo extends StatelessWidget {
  const _LoginLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/sobatnira/art/ukaisya-logo.png',
    width: width,
    fit: BoxFit.contain,
    semanticLabel: 'Ukaisya, PT Tiga Dewi Timur Raya',
  );
}
