import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'settings_demo.dart';
import 'settings_widgets.dart';

class SettingsGeneralPage extends StatelessWidget {
  const SettingsGeneralPage({
    required this.entry,
    required this.settings,
    required this.onNavigate,
    super.key,
  });

  final SettingEntry entry;
  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: entry.title,
    subtitle: entry.subtitle,
    onNavigate: onNavigate,
    children: switch (entry.section) {
      SettingSection.identity => [_identity(context)],
      SettingSection.rules => _rules(context),
      _ => throw ArgumentError.value(entry.section, 'section'),
    },
  );

  Widget _identity(BuildContext context) {
    final factory = settings.factory;
    return SettingsForm(
      fields: [
        SettingsField('Nama pabrik', initial: factory.name),
        SettingsField('Kode pabrik', initial: factory.code),
        SettingsField('Cabang', initial: factory.branch),
        SettingsField(
          'Zona waktu',
          initial: factory.timezone,
          options: const ['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura'],
        ),
      ],
      onSave: (values) {
        settings.saveFactory((
          name: values['Nama pabrik']!,
          code: values['Kode pabrik']!,
          branch: values['Cabang']!,
          timezone: values['Zona waktu']!,
        ));
        showSettingsSaved(context);
      },
      onCancel: () => Navigator.maybePop(context),
    );
  }

  List<Widget> _rules(BuildContext context) => [
    const SettingsNote(
      'Batas volume di bawah berlaku untuk konfigurasi demo. '
      'Field ISI pada Nota Produksi dicatat dalam kilogram.',
    ),
    const SizedBox(height: 15),
    const _RuleDetail(
      'Campuran antar kloter',
      'Catat volume dari setiap kloter asal. Alokasi memakai proporsi liter '
          'setelah batch penerima tervalidasi.',
    ),
    const _RuleDetail(
      'Masak ulang',
      'Catat berat gula yang dipakai serta batch asal dan penerima. '
          'Dampaknya pada kapasitas dan nilai masih perlu dikonfirmasi.',
    ),
    const _RuleDetail(
      'Konversi satuan',
      'Konversi dari ISI dalam kg ke volume kontribusi dalam liter '
          'masih menunggu keputusan.',
    ),
    const SizedBox(height: 16),
    SettingsForm(
      fields: [
        SettingsField(
          'Batas volume batch',
          initial: settings.batchLimit,
          suffix: 'L',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: validatePositiveDecimal,
        ),
      ],
      onSave: (values) {
        settings.saveBatchLimit(values['Batas volume batch']!);
        showSettingsSaved(context);
      },
      onCancel: () => Navigator.maybePop(context),
    ),
  ];
}

class _RuleDetail extends StatelessWidget {
  const _RuleDetail(this.title, this.description);

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: niraText(NiraType.section, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        SettingsNote(description),
      ],
    ),
  );
}
