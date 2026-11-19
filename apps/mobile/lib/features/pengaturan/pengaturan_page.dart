import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'harga_biaya_page.dart';
import 'settings_catalog_page.dart';
import 'settings_demo.dart';
import 'settings_forms_page.dart';
import 'settings_general_page.dart';

class PengaturanPage extends StatelessWidget {
  const PengaturanPage({
    required this.settings,
    required this.onNavigate,
    this.connectedProfile,
    this.onConnectedEntry,
    this.onOpenPekerjaan,
    this.onSignOut,
    this.catalogLinks = const {},
    super.key,
  });

  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;
  final String? connectedProfile;
  final Map<SettingSection, VoidCallback>? onConnectedEntry;
  final VoidCallback? onOpenPekerjaan;
  final VoidCallback? onSignOut;
  final Map<String, VoidCallback> catalogLinks;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => ListView(
      key: const PageStorageKey('pengaturan-scroll'),
      padding: EdgeInsets.fromLTRB(
        niraPageInset(context),
        NiraSpace.lg,
        niraPageInset(context),
        NiraSpace.lg,
      ),
      children: [
        _profile(),
        const SizedBox(height: NiraSpace.xl),
        _section('PABRIK & TIM', factoryEntries, context),
        if (onOpenPekerjaan case final open?)
          _menuRow('Pekerjaan', 'Tinjau nota dari pabrik aktif', 'form', open),
        const SizedBox(height: NiraSpace.xl),
        _section('PRODUKSI & PERHITUNGAN', productionEntries, context),
        for (final entry in catalogLinks.entries)
          _menuRow(
            entry.key,
            'Kelola daftar ${entry.key.toLowerCase()}',
            entry.key == 'Pemasok' ? 'people' : 'science',
            entry.value,
          ),
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: const Text('Keluar')),
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
        connectedProfile ?? settings.accounts.first.value.name,
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

  Widget _row(SettingEntry entry, BuildContext context) {
    final callbacks = onConnectedEntry;
    final VoidCallback? open = callbacks == null
        ? () => _open(context, entry)
        : callbacks[entry.section];
    return _menuRow(entry.title, entry.subtitle, entry.icon, open);
  }

  Widget _menuRow(
    String title,
    String subtitle,
    String icon,
    VoidCallback? open,
  ) {
    return Semantics(
      label: title,
      button: open != null,
      enabled: open != null,
      onTap: open,
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
          child: Row(
            children: [
              _SettingIcon(icon),
              const SizedBox(width: NiraSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: niraText(NiraType.body, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: NiraSpace.xs),
                    Text(
                      open == null ? 'Belum tersedia' : subtitle,
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                  ],
                ),
              ),
              if (open != null)
                const Icon(Icons.chevron_right, color: niraGreen, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, SettingEntry entry) {
    final page = switch (entry.section) {
      SettingSection.prices => HargaBiayaPage(
        settings: settings,
        onNavigate: onNavigate,
      ),
      SettingSection.identity || SettingSection.rules => SettingsGeneralPage(
        entry: entry,
        settings: settings,
        onNavigate: onNavigate,
      ),
      SettingSection.forms => SettingsFormsPage(
        settings: settings,
        onNavigate: onNavigate,
      ),
      _ => SettingsCatalogPage(
        entry: entry,
        settings: settings,
        onNavigate: onNavigate,
      ),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final icon = switch (name) {
      'facilities' => Icons.precision_manufacturing,
      'people' => Icons.groups,
      'schedule' => Icons.watch_later,
      'security' => Icons.admin_panel_settings,
      'rule' => Icons.fact_check,
      'grade' => Icons.workspace_premium,
      'science' => Icons.science,
      'form' => Icons.assignment,
      'calculator' => Icons.calculate,
      _ => Icons.factory,
    };
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(child: Icon(icon, size: 28, color: niraGreen)),
    );
  }
}
