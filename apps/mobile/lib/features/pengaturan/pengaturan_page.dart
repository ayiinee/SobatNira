import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'harga_biaya_page.dart';
import 'settings_demo.dart';
import 'settings_placeholder_page.dart';

class PengaturanPage extends StatelessWidget {
  const PengaturanPage({
    required this.settings,
    required this.onNavigate,
    super.key,
  });

  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => ListView(
      key: const PageStorageKey('pengaturan-scroll'),
      padding: const EdgeInsets.fromLTRB(niraInset, 13, niraInset, 88),
      children: [
        _profile(),
        const SizedBox(height: 18),
        _section('PABRIK & TIM', factoryEntries, context),
        const SizedBox(height: 15),
        _section('PRODUKSI & PERHITUNGAN', productionEntries, context),
      ],
    ),
  );

  Widget _profile() => Column(
    children: [
      ClipOval(
        child: Image.asset(
          'assets/sobatnira/art/profil-demo.png',
          width: 58,
          height: 58,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(height: 5),
      Text('Pak Putu Alvin', style: niraText(15, weight: FontWeight.w700)),
    ],
  );

  Widget _section(
    String title,
    List<SettingEntry> entries,
    BuildContext context,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: niraText(10.5, color: niraLeaf, weight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      for (final entry in entries) _row(entry, context),
    ],
  );

  Widget _row(SettingEntry entry, BuildContext context) => Semantics(
    label: entry.title,
    button: true,
    onTap: () => _open(context, entry),
    excludeSemantics: true,
    child: InkWell(
      onTap: () => _open(context, entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _SettingIcon(entry.icon),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: niraText(12.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(entry.subtitle, style: niraText(10.5, color: niraLeaf)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: niraGreen, size: 20),
          ],
        ),
      ),
    ),
  );

  void _open(BuildContext context, SettingEntry entry) {
    final page = entry.title == 'Harga & Biaya'
        ? HargaBiayaPage(settings: settings, onNavigate: onNavigate)
        : SettingsPlaceholderPage(entry: entry, onNavigate: onNavigate);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final icon = switch (name) {
      'people' => Icons.groups_outlined,
      'schedule' => Icons.access_time_rounded,
      'security' => Icons.group_outlined,
      'rule' => Icons.settings_suggest_outlined,
      'grade' => Icons.workspace_premium_outlined,
      'science' => Icons.science_outlined,
      'form' => Icons.description_outlined,
      'calculator' => Icons.calculate_outlined,
      _ => Icons.factory_outlined,
    };
    return Icon(icon, size: 30, color: niraGreen);
  }
}
