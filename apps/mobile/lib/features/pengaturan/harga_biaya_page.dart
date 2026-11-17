import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'settings_demo.dart';
import 'settings_widgets.dart';

class HargaBiayaPage extends StatefulWidget {
  const HargaBiayaPage({
    required this.settings,
    required this.onNavigate,
    this.operationalFirst = false,
    this.unavailable = false,
    super.key,
  });

  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;
  final bool operationalFirst;
  final bool unavailable;

  @override
  State<HargaBiayaPage> createState() => _HargaBiayaPageState();
}

class _HargaBiayaPageState extends State<HargaBiayaPage> {
  final _form = GlobalKey<FormState>();
  late final _grades = widget.settings.grades
      .where((grade) => grade.active)
      .toList();
  late final _prices = {
    for (final grade in _grades)
      grade.id: TextEditingController(text: widget.settings.priceFor(grade.id)),
  };
  late final _cost = TextEditingController(
    text: widget.settings.operationalCost,
  );

  @override
  void dispose() {
    for (final controller in _prices.values) {
      controller.dispose();
    }
    _cost.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final prices = {
      for (final entry in _prices.entries)
        entry.key: _formatRupiah(entry.value.text.trim()),
    };
    final cost = _formatRupiah(_cost.text.trim());
    widget.settings.savePrices(prices, cost);

    for (final entry in prices.entries) {
      _prices[entry.key]!.text = entry.value;
    }
    _cost.text = cost;
    FocusScope.of(context).unfocus();
    showSettingsSaved(
      context,
      message: 'Perubahan harga tersimpan selama sesi demo',
    );
  }

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: widget.operationalFirst ? 'Biaya Operasional' : 'Harga & Biaya',
    tab: widget.operationalFirst ? NiraTab.beranda : NiraTab.pengaturan,
    onNavigate: widget.onNavigate,
    subtitle: 'Harga jual per grade dan biaya operasional',
    bottomAction: NiraButton(
      'Simpan perubahan',
      widget.unavailable ? null : _save,
    ),
    children: [
      if (widget.unavailable)
        const SettingsNote('Data harga dan biaya operasional belum tersedia.')
      else
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.operationalFirst) ...[
                ..._operationalFields(),
                const SizedBox(height: NiraSpace.lg),
              ],
              Text(
                'Harga per grade',
                style: niraText(NiraType.section, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const SettingsNote('Harga jual gula per kilogram'),
              const SizedBox(height: 12),
              if (_grades.isEmpty) const SettingsNote('Belum ada grade aktif.'),
              for (final grade in _grades)
                Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: _moneyField(
                    label: grade.value.name,
                    controller: _prices[grade.id]!,
                    unit: '/kg',
                    optional: widget.settings.priceFor(grade.id) == null,
                  ),
                ),
              if (!widget.operationalFirst) ...[
                const SizedBox(height: 6),
                ..._operationalFields(),
              ],
              const SizedBox(height: 14),
              const SettingsNote('Perubahan tersimpan selama sesi demo.'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Batal'),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  List<Widget> _operationalFields() => [
    _moneyField(label: 'Biaya Operasional', controller: _cost, unit: '/kloter'),
    const SizedBox(height: 7),
    const SettingsNote('Dikenakan satu kali setiap kloter'),
  ];

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required String unit,
    bool optional = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    style: niraText(NiraType.body, weight: FontWeight.w600),
    decoration: settingsInputDecoration(
      label,
      prefix: 'Rp ',
      suffix: unit,
      hint: optional ? 'Belum diatur' : null,
    ),
    validator: (input) {
      final value = input?.trim() ?? '';
      if (value.isEmpty && optional) return null;
      return RegExp(r'^(?:\d+|\d{1,3}(?:\.\d{3})+)$').hasMatch(value)
          ? null
          : 'Masukkan harga dalam Rupiah.';
    },
  );
}

String _formatRupiah(String value) {
  final digits = value
      .replaceAll('.', '')
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}
