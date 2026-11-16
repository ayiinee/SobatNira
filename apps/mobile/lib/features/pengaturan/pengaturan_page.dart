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
      padding: EdgeInsets.fromLTRB(
        niraInset,
        NiraSpace.lg,
        niraInset,
        NiraSpace.lg,
      ),
      children: [
        _profile(),
        const SizedBox(height: NiraSpace.xl),
        _section('PABRIK & TIM', factoryEntries, context),
        const SizedBox(height: NiraSpace.xl),
        _section('PRODUKSI & PERHITUNGAN', productionEntries, context),
      ],
    ),
  );

  Widget _profile() => Column(
    children: [
      ClipOval(
        child: Image.asset(
          'assets/sobatnira/art/profil-demo.png',
          width: 64,
          height: 64,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(height: NiraSpace.xs),
      Text(
        'Pak Putu Alvin',
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
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
        style: niraText(
          NiraType.caption,
          color: niraLeaf,
          weight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: NiraSpace.xs),
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
        padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
        child: Row(
          children: [
            _SettingIcon(entry.icon),
            const SizedBox(width: NiraSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: niraText(NiraType.body, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: NiraSpace.xs),
                  Text(
                    entry.subtitle,
                    style: niraText(NiraType.caption, color: niraLeaf),
                  ),
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
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E8),
        borderRadius: BorderRadius.circular(niraRadius),
      ),
      child: Icon(icon, size: 24, color: niraGreen),
    );
  }
}
