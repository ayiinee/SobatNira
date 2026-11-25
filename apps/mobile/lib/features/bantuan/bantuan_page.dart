import 'package:flutter/material.dart';
import 'open_support_url.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/nira_loading.dart';
import '../pekerjaan/review_api.dart';
import '../pengaturan/settings_widgets.dart';

const supportPhone = '085337236836';

Uri supportWhatsAppUri(String message, {String phone = '+6285337236836'}) =>
    Uri.https('wa.me', '/${phone.substring(1)}', {'text': message.trim()});

class BantuanPage extends StatefulWidget {
  const BantuanPage({required this.onNavigate, this.loadProfile, super.key});
  final ValueChanged<NiraTab> onNavigate;
  final Future<Json> Function()? loadProfile;

  @override
  State<BantuanPage> createState() => _BantuanPageState();
}

class _BantuanPageState extends State<BantuanPage> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  bool _opening = false;
  String? _error;
  late Future<Json>? _profile = widget.loadProfile?.call();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit(String phone) async {
    if (_opening || !_form.currentState!.validate()) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      // Launch immediately from the user's gesture so web popup blockers allow it.
      final opened = await openSupportUrl(
        supportWhatsAppUri(_message.text, phone: phone),
      );
      if (!opened && mounted) {
        setState(
          () => _error =
              'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profile case final profile?) {
      return FutureBuilder<Json>(
        future: profile,
        builder: (context, snapshot) {
          final phone = snapshot.data?['supportPhone'];
          return _page(
            phone is String && RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)
                ? phone
                : null,
            loading: snapshot.connectionState != ConnectionState.done,
            failed: snapshot.hasError,
          );
        },
      );
    }
    return _page('+6285337236836', display: supportPhone);
  }

  Widget _page(
    String? phone, {
    String? display,
    bool loading = false,
    bool failed = false,
  }) => SettingsPageFrame(
    title: 'Bantuan',
    tab: NiraTab.beranda,
    hideNavigationWhileEditing: true,
    onNavigate: widget.onNavigate,
    subtitle: 'Ceritakan kendala atau pertanyaanmu.',
    children: [
      if (loading)
        const NiraLoading(label: 'Memuat kontak bantuan…')
      else if (failed)
        SettingsLoadError(
          accessDenied: false,
          message: 'Kontak bantuan belum bisa dimuat.',
          onRetry: () => setState(() => _profile = widget.loadProfile?.call()),
        )
      else if (phone == null)
        const SettingsNote(
          'Kontak WhatsApp bantuan belum diatur untuk pabrik ini.',
        )
      else ...[
        Text(
          'Hubungi melalui WhatsApp',
          style: niraText(NiraType.section, weight: FontWeight.w600),
        ),
        const SizedBox(height: NiraSpace.xs),
        SelectableText(
          display ?? phone,
          style: niraText(NiraType.body, weight: FontWeight.w600),
        ),
        const SizedBox(height: NiraSpace.lg),
        Form(
          key: _form,
          child: TextFormField(
            controller: _message,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
            ).copyWith(alignLabelWithHint: true),
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
          _opening ? null : () => _submit(phone),
        ),
        const SizedBox(height: NiraSpace.lg),
      ],
    ],
  );
}
