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
      padding: const EdgeInsets.fromLTRB(niraInset, 6, niraInset, 14),
      children: [
        DetailTitle(entry.title),
        const SizedBox(height: 12),
        NiraOutline(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: niraText(18, weight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(entry.subtitle, style: niraText(12, color: niraLeaf)),
                const SizedBox(height: 16),
                const Icon(
                  Icons.construction_outlined,
                  size: 30,
                  color: niraGreen,
                ),
                const SizedBox(height: 7),
                Text(
                  'Detail konfigurasi tersedia pada tahap berikutnya.',
                  style: niraText(12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tampilan ini mengikuti navigasi Pengaturan dan memakai data sintetis.',
                  style: niraText(11, color: niraLeaf),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
