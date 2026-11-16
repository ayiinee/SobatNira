import 'package:flutter/material.dart';

import 'review_api.dart';
import 'review_detail_page.dart';

class PekerjaanPage extends StatefulWidget {
  const PekerjaanPage({this.api, super.key});
  final ReviewApi? api;

  @override
  State<PekerjaanPage> createState() => _PekerjaanPageState();
}

class _PekerjaanPageState extends State<PekerjaanPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  ReviewApi? _session;
  Future<List<Json>>? _tasks;
  String _status = 'PENDING_VALIDATION';
  int _page = 1;
  bool _signingIn = false;
  String? _error;

  ReviewApi? get _api => widget.api ?? _session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _session?.close();
    super.dispose();
  }

  void _load() {
    _tasks = _api?.list(_status, _page);
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final session = await ReviewApi.signIn(
        _email.text.trim(),
        _password.text,
      );
      if (!mounted) {
        session.close();
        return;
      }
      _password.clear();
      setState(() {
        _session = session;
        _load();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal masuk. Periksa akun dan koneksi.');
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _signOut() {
    _session?.close();
    setState(() {
      _session = null;
      _tasks = null;
      _page = 1;
    });
  }

  Future<void> _open(Json task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ReviewDetailPage(api: _api!, taskId: task['id'] as String),
      ),
    );
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Pekerjaan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (_session != null)
            TextButton(onPressed: _signOut, child: const Text('Keluar')),
        ],
      ),
      const SizedBox(height: 16),
      if (_api == null)
        ..._login()
      else ...[
        DropdownButton<String>(
          value: _status,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'PENDING_VALIDATION',
              child: Text('Menunggu validasi'),
            ),
            DropdownMenuItem(value: 'VALIDATED', child: Text('Tervalidasi')),
            DropdownMenuItem(
              value: 'RETURNED_FOR_CORRECTION',
              child: Text('Dikembalikan'),
            ),
            DropdownMenuItem(
              value: 'MANUAL_REVIEW_REQUIRED',
              child: Text('Perlu tinjauan manual'),
            ),
          ],
          onChanged: (value) => setState(() {
            _status = value!;
            _page = 1;
            _load();
          }),
        ),
        FutureBuilder<List<Json>>(
          future: _tasks,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Column(
                children: [
                  Text(
                    error is ReviewApiError
                        ? error.message
                        : 'Gagal memuat antrean.',
                  ),
                  TextButton(
                    onPressed:
                        error is ReviewApiError &&
                            error.status == 401 &&
                            _session != null
                        ? _signOut
                        : () => setState(_load),
                    child: const Text('Coba lagi'),
                  ),
                ],
              );
            }
            final tasks = snapshot.data ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tasks.isEmpty)
                  const Text('Belum ada laporan pada status ini.'),
                for (final task in tasks)
                  Card(
                    child: ListTile(
                      title: Text(documentType(task['document_type'])),
                      subtitle: Text(
                        '${task['sender_name']} · Revisi ${task['version']} · ${task['issue_count']} temuan',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(task),
                    ),
                  ),
                if (_page > 1 || tasks.length == 20)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _page > 1
                            ? () => setState(() {
                                _page--;
                                _load();
                              })
                            : null,
                        child: const Text('Sebelumnya'),
                      ),
                      Text('$_page'),
                      TextButton(
                        onPressed: tasks.length == 20
                            ? () => setState(() {
                                _page++;
                                _load();
                              })
                            : null,
                        child: const Text('Berikutnya'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    ],
  );

  List<Widget> _login() {
    if (supabaseProject.isEmpty || supabasePublicKey.isEmpty) {
      return [
        const Text('Akses Pekerjaan belum dikonfigurasi untuk build ini.'),
      ];
    }
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Kata sandi'),
        onSubmitted: (_) {
          if (!_signingIn) _signIn();
        },
      ),
      if (_error != null) Text(_error!),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _signingIn ? null : _signIn,
        child: Text(_signingIn ? 'Memproses…' : 'Masuk'),
      ),
    ];
  }
}
