import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'settings_demo.dart';
import 'settings_widgets.dart';

typedef _Mapping = ({String label, String field, String unit, String? note});

const _arrival = <_Mapping>[
  (label: 'Tanggal', field: 'arrival_date', unit: 'Tanggal', note: null),
  (label: 'Pengirim', field: 'supplier_name', unit: 'Teks', note: null),
  (label: 'No. kendaraan', field: 'vehicle_number', unit: 'Teks', note: null),
  (
    label: 'Brix',
    field: 'brix',
    unit: 'Satuan belum ditetapkan',
    note: 'Titik pengukuran menunggu konfirmasi.',
  ),
  (label: 'Berat bersih', field: 'net_weight_kg', unit: 'kg', note: null),
  (label: 'Jenis tebu', field: 'cane_type', unit: 'Kode', note: null),
  (label: 'Operator', field: 'receiving_operator', unit: 'Teks', note: null),
  (
    label: 'Label tebu',
    field: 'cane_tag_reference',
    unit: 'Teks',
    note:
        'Format label dan status saat label tidak tersedia menunggu konfirmasi.',
  ),
];

const _production = <_Mapping>[
  (label: 'Tgl', field: 'production_date', unit: 'Tanggal', note: null),
  (label: 'Sif', field: 'shift', unit: 'Kode atau teks', note: null),
  (label: 'Chef', field: 'chef', unit: 'Teks', note: null),
  (
    label: 'Tebu',
    field: 'cane_label',
    unit: 'Teks',
    note: 'Format representasi label menunggu konfirmasi.',
  ),
  (label: 'Wajan', field: 'pan_number', unit: 'Kode', note: null),
  (
    label: 'Brix',
    field: 'brix',
    unit: 'Satuan belum ditetapkan',
    note: 'Tahap pengukuran menunggu konfirmasi.',
  ),
  (label: 'Isi', field: 'isi_kg', unit: 'kg', note: null),
  (label: 'Gamping', field: 'gamping', unit: 'Takaran asli', note: null),
  (label: 'Jam turun', field: 'jam_turun', unit: 'Waktu', note: null),
  (label: 'Grade', field: 'grade', unit: 'Kode', note: null),
  (label: 'Hasil', field: 'hasil_kg', unit: 'kg', note: null),
];

class SettingsFormsPage extends StatefulWidget {
  const SettingsFormsPage({this.settings, required this.onNavigate, super.key});

  final SettingsDemo? settings;
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<SettingsFormsPage> createState() => _SettingsFormsPageState();
}

class _SettingsFormsPageState extends State<SettingsFormsPage> {
  var _selected = 0;

  Future<void> _addAlias(
    _Mapping mapping,
    List<_Mapping> mappings,
    String template,
  ) async {
    final settings = widget.settings;
    if (settings == null) return;
    final field = '$template.${mapping.field}';
    final result = await showSettingsEditor(
      context,
      title: 'Alias untuk ${mapping.label}',
      fields: [
        SettingsField(
          'Label OCR tambahan',
          validator: (label) {
            final query = label.toLowerCase();
            for (final other in mappings) {
              final otherKey = '$template.${other.field}';
              if (other.label.toLowerCase() == query ||
                  settings
                      .aliasesFor(otherKey)
                      .any((alias) => alias.toLowerCase() == query)) {
                return 'Label ini sudah digunakan pada formulir.';
              }
            }
            return null;
          },
        ),
      ],
    );
    if (result == null || !mounted) return;
    settings.addAlias(field, result['Label OCR tambahan']!);
    showSettingsSaved(context);
  }

  @override
  Widget build(BuildContext context) {
    final mappings = _selected == 0 ? _arrival : _production;
    final template = _selected == 0 ? 'arrival' : 'production';
    final settings = widget.settings;
    Widget page() => SettingsPageFrame(
      title: 'Formulir produksi',
      subtitle: 'Pratinjau kolom dan pemetaan OCR',
      onNavigate: widget.onNavigate,
      keepTitleVisible: settings == null,
      children: [
        SettingsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selected,
                decoration: settingsInputDecoration('Jenis nota'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 0,
                    child: Text('Nota Kedatangan Truk'),
                  ),
                  DropdownMenuItem(value: 1, child: Text('Nota Produksi')),
                ],
                onChanged: (value) => setState(() => _selected = value ?? 0),
              ),
              const SizedBox(height: NiraSpace.md),
              Text(
                'Kolom wajib tetap ada meski nilainya belum diisi atau tidak terbaca.'
                '${settings == null ? '' : ' Alias disimpan sebagai draf demo.'}',
                style: niraText(NiraType.body, color: niraLeaf),
              ),
            ],
          ),
        ),
        const SizedBox(height: NiraSpace.md),
        SettingsPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < mappings.length; index++) ...[
                if (index > 0) const Divider(height: 1, color: niraLine),
                _mappingRow(mappings[index], mappings, template),
              ],
            ],
          ),
        ),
        if (_selected == 1) ...[
          const SizedBox(height: NiraSpace.md),
          const SettingsMessage(
            icon: Icons.info_outline,
            message:
                'Kolom yang belum terpetakan tetap dicatat dengan label mentah.',
          ),
        ],
      ],
    );
    return settings == null
        ? page()
        : ListenableBuilder(listenable: settings, builder: (_, _) => page());
  }

  Widget _mappingRow(
    _Mapping mapping,
    List<_Mapping> mappings,
    String template,
  ) {
    final key = '$template.${mapping.field}';
    final settings = widget.settings;
    final aliases = settings?.aliasesFor(key) ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mapping.label,
                      style: niraText(
                        NiraType.section,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: NiraSpace.xs),
                    Text(
                      '${mapping.field} · ${mapping.unit}',
                      style: niraText(NiraType.body, color: niraLeaf),
                    ),
                    if (settings != null)
                      const SettingsNote('Wajib pada skema'),
                    if (mapping.note != null) ...[
                      const SizedBox(height: NiraSpace.xs),
                      SettingsNote(mapping.note!),
                    ],
                  ],
                ),
              ),
              if (settings != null && mapping.note == null)
                IconButton(
                  tooltip: 'Tambah alias ${mapping.label}',
                  onPressed: () => _addAlias(mapping, mappings, template),
                  icon: const Icon(Icons.add, color: niraGreen),
                ),
            ],
          ),
          if (settings != null && aliases.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 3,
              children: [
                for (final alias in aliases)
                  InputChip(
                    label: Text(alias),
                    deleteButtonTooltipMessage: 'Hapus alias $alias',
                    onDeleted: () => settings.removeAlias(key, alias),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
