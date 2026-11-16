import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'settings_demo.dart';

class SettingsPlaceholderPage extends StatelessWidget {
  const SettingsPlaceholderPage({
    required this.entry,
    required this.onNavigate,
    super.key,
  });

  final SettingEntry entry;
  final ValueChanged<NiraTab> onNavigate;

  @override
  Widget build(BuildContext context) => NiraScaffold(
    tab: NiraTab.pengaturan,
    onNavigate: onNavigate,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        niraInset,
        NiraSpace.sm,
        niraInset,
        NiraSpace.lg,
      ),
      children: [
        DetailTitle(entry.title, inset: 0),
        const SizedBox(height: NiraSpace.md),
        NiraOutline(
          Padding(
            padding: const EdgeInsets.all(NiraSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: niraText(NiraType.section, weight: FontWeight.w700),
                ),
                const SizedBox(height: NiraSpace.xs),
                Text(
                  entry.subtitle,
                  style: niraText(NiraType.caption, color: niraLeaf),
                ),
                const SizedBox(height: NiraSpace.lg),
                const Icon(
                  Icons.construction_outlined,
                  size: 30,
                  color: niraGreen,
                ),
                const SizedBox(height: NiraSpace.sm),
                Text(
                  'Detail konfigurasi tersedia pada tahap berikutnya.',
                  style: niraText(NiraType.body),
                ),
                const SizedBox(height: NiraSpace.xs),
                Text(
                  'Tampilan ini mengikuti navigasi Pengaturan dan memakai data sintetis.',
                  style: niraText(NiraType.caption, color: niraLeaf),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
