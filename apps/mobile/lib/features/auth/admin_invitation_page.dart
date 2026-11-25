import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/page_frame.dart';
import '../pekerjaan/review_api.dart';

class AdminInvitationPage extends StatefulWidget {
  const AdminInvitationPage({
    required this.token,
    required this.onDone,
    super.key,
  });

  final String token;
  final VoidCallback onDone;

  @override
  State<AdminInvitationPage> createState() => _AdminInvitationPageState();
}

class _AdminInvitationPageState extends State<AdminInvitationPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ReviewApi.completeInvitation(widget.token, _password.text);
      if (mounted) widget.onDone();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          ReviewApiError(status: 401 || 403) =>
            'Undangan kedaluwarsa atau tidak berlaku. Hubungi pengelola.',
          ReviewApiError(status: 400 || 422) =>
            'Kata sandi ditolak. Coba kata sandi lain.',
          _ => 'Kata sandi belum tersimpan. Periksa koneksi dan coba lagi.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => NiraPageScaffold(
    title: const Text('Undangan admin'),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(NiraSpace.lg),
          children: [
            const Text('Atur kata sandi untuk akun yang diundang.'),
            const SizedBox(height: NiraSpace.md),
            TextFormField(
              enabled: !_busy,
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Kata sandi baru'),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Isi kata sandi.' : null,
            ),
            TextFormField(
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Ulangi kata sandi'),
              validator: (value) =>
                  value != _password.text ? 'Kata sandi belum sama.' : null,
            ),
            if (_error case final error?) Text(error),
            const SizedBox(height: NiraSpace.md),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Menyimpan…' : 'Simpan kata sandi'),
            ),
          ],
        ),
      ),
    ),
  );
}
