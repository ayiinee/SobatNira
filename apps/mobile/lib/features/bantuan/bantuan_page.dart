import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../sobatnira_ui.dart';
import '../pengaturan/settings_widgets.dart';

const supportPhone = '085337236836';

Uri supportWhatsAppUri(String message) =>
    Uri.https('wa.me', '/6285337236836', {'text': message.trim()});

class BantuanPage extends StatefulWidget {
  const BantuanPage({required this.onNavigate, super.key});
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<BantuanPage> createState() => _BantuanPageState();
}

class _BantuanPageState extends State<BantuanPage> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_opening || !_form.currentState!.validate()) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      // Launch immediately from the user's gesture so web popup blockers allow it.
      final opened = await launchUrl(
        supportWhatsAppUri(_message.text),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted)
        setState(
          () => _error =
              'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'Bantuan',
    tab: NiraTab.beranda,
    onNavigate: widget.onNavigate,
    subtitle: 'Ceritakan kendala atau pertanyaanmu.',
    children: [
      Text(
        'Hubungi melalui WhatsApp',
        style: niraText(NiraType.section, weight: FontWeight.w600),
      ),
      const SizedBox(height: NiraSpace.xs),
      SelectableText(
        supportPhone,
        style: niraText(NiraType.body, weight: FontWeight.w600),
      ),
      const SizedBox(height: NiraSpace.lg),
      Form(
        key: _form,
        child: TextFormField(
          controller: _message,
          minLines: 5,
          maxLines: 10,
          maxLength: 1500,
          readOnly: _opening,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: niraText(NiraType.body),
          decoration: settingsInputDecoration(
            'Pesan bantuan',
            hint: 'Tulis pertanyaan atau kendala yang kamu alami…',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Tulis pesan terlebih dahulu.'
              : null,
        ),
      ),
      const SizedBox(height: NiraSpace.sm),
      const SettingsNote(
        'Pesan akan dibuka di WhatsApp. Tekan Kirim di sana untuk mengirimkannya.',
      ),
      if (_error != null) ...[
        const SizedBox(height: NiraSpace.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: niraText(NiraType.body, color: niraOchre),
          ),
        ),
      ],
      const SizedBox(height: NiraSpace.lg),
      NiraButton(
        _opening ? 'Membuka WhatsApp…' : 'Kirim via WhatsApp',
        _opening ? null : _submit,
      ),
      const SizedBox(height: NiraSpace.lg),
    ],
  );
}
