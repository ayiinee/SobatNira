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
      padding: const EdgeInsets.fromLTRB(niraInset, 6, niraInset, 8),
      children: [
        const DetailTitle('Harga & Biaya'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: niraInset),
          child: Text(
            'Berlaku untuk seluruh kloter dan batch',
            style: niraText(11.5, color: niraLeaf),
          ),
        ),
        const SizedBox(height: 17),
        const _SectionLabel('Harga per grade', 'Harga jual gula per kilogram'),
        const SizedBox(height: 13),
        _MoneyField('Grade A', _a, '/kg'),
        _MoneyField('Grade B', _b, '/kg'),
        _MoneyField('Grade C', _c, '/kg'),
        const SizedBox(height: 14),
        _MoneyField('Biaya Operasional', _cost, '/kloter'),
        const SizedBox(height: 7),
        Text(
          'Dikenakan satu kali setiap kloter',
          style: niraText(10, color: niraMuted),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 17, color: niraLeaf),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Perubahan berlaku untuk produksi selanjutnya. Data terdahulu tetap menggunakan nilai sebelumnya.',
                style: niraText(9.5, color: niraLeaf),
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
      Text(title, style: niraText(14, weight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(subtitle, style: niraText(11, color: niraLeaf)),
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
    padding: const EdgeInsets.only(top: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: niraText(11.5, weight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: niraText(13, weight: FontWeight.w600),
          decoration: InputDecoration(
            prefixText: 'Rp  ',
            suffixText: suffix,
            prefixStyle: niraText(12, color: niraLeaf),
            suffixStyle: niraText(11, color: niraLeaf),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: niraGreen, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: niraGreen, width: 2),
            ),
          ),
        ),
      ],
    ),
  );
}
