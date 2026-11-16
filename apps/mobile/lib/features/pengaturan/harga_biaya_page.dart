import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'settings_demo.dart';

class HargaBiayaPage extends StatefulWidget {
  const HargaBiayaPage({
    required this.settings,
    required this.onNavigate,
    super.key,
  });

  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<HargaBiayaPage> createState() => _HargaBiayaPageState();
}

class _HargaBiayaPageState extends State<HargaBiayaPage> {
  late final _a = TextEditingController(text: widget.settings.gradeA);
  late final _b = TextEditingController(text: widget.settings.gradeB);
  late final _c = TextEditingController(text: widget.settings.gradeC);
  late final _cost = TextEditingController(
    text: widget.settings.operationalCost,
  );

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _c.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _save() {
    final values = [_a.text, _b.text, _c.text, _cost.text];
    if (values.any(
      (value) => !RegExp(r'^\d+(?:[.]\d{3})?$').hasMatch(value.trim()),
    )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Gunakan angka dengan format harga yang valid.'),
          ),
        );
      return;
    }
    widget.settings.update(
      a: _a.text.trim(),
      b: _b.text.trim(),
      c: _c.text.trim(),
      cost: _cost.text.trim(),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Perubahan harga tersimpan selama sesi demo'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => NiraScaffold(
    tab: NiraTab.pengaturan,
    onNavigate: widget.onNavigate,
    bottomAction: NiraButton('Simpan perubahan', _save),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        niraInset,
        NiraSpace.sm,
        niraInset,
        NiraSpace.sm,
      ),
      children: [
        const DetailTitle('Harga & Biaya', inset: 0),
        Text(
          'Berlaku untuk seluruh kloter dan batch',
          style: niraText(NiraType.caption, color: niraLeaf),
        ),
        const SizedBox(height: NiraSpace.lg),
        const _SectionLabel('Harga per grade', 'Harga jual gula per kilogram'),
        const SizedBox(height: NiraSpace.xs),
        _MoneyField('Grade A', _a, '/kg'),
        _MoneyField('Grade B', _b, '/kg'),
        _MoneyField('Grade C', _c, '/kg'),
        const SizedBox(height: NiraSpace.lg),
        _MoneyField('Biaya Operasional', _cost, '/kloter'),
        const SizedBox(height: NiraSpace.sm),
        Text(
          'Dikenakan satu kali setiap kloter',
          style: niraText(NiraType.caption, color: niraLeaf),
        ),
        const SizedBox(height: NiraSpace.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 17, color: niraLeaf),
            const SizedBox(width: NiraSpace.xs),
            Expanded(
              child: Text(
                'Perubahan berlaku untuk produksi selanjutnya. Data terdahulu tetap menggunakan nilai sebelumnya.',
                style: niraText(NiraType.caption, color: niraLeaf),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: niraText(NiraType.section, weight: FontWeight.w600)),
      const SizedBox(height: NiraSpace.xs),
      Text(subtitle, style: niraText(NiraType.caption, color: niraLeaf)),
    ],
  );
}

class _MoneyField extends StatelessWidget {
  const _MoneyField(this.label, this.controller, this.suffix);
  final String label;
  final TextEditingController controller;
  final String suffix;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NiraSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: niraText(NiraType.body, weight: FontWeight.w600)),
        const SizedBox(height: NiraSpace.xs),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: niraText(NiraType.body, weight: FontWeight.w600),
          decoration: InputDecoration(
            prefixText: 'Rp  ',
            suffixText: suffix,
            prefixStyle: niraText(NiraType.body, color: niraLeaf),
            suffixStyle: niraText(NiraType.caption, color: niraLeaf),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NiraSpace.lg,
              vertical: NiraSpace.lg,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(niraRadius),
              borderSide: const BorderSide(color: niraGreen, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(niraRadius),
              borderSide: const BorderSide(color: niraGreen, width: 2),
            ),
          ),
        ),
      ],
    ),
  );
}
