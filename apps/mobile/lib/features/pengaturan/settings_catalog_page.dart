import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'harga_biaya_page.dart';
import 'settings_demo.dart';
import 'settings_widgets.dart';

const _status = 'Status';
const _active = 'Aktif';
const _inactive = 'Nonaktif';

class SettingsCatalogPage extends StatelessWidget {
  const SettingsCatalogPage({
    required this.entry,
    required this.settings,
    required this.onNavigate,
    super.key,
  });

  final SettingEntry entry;
  final SettingsDemo settings;
  final ValueChanged<NiraTab> onNavigate;

  @override
  Widget build(BuildContext context) => switch (entry.section) {
    SettingSection.facilities => _facilities(),
    SettingSection.operators => _operators(),
    SettingSection.shifts => _shifts(),
    SettingSection.access => _accounts(),
    SettingSection.grades => _grades(context),
    SettingSection.additives => _additives(),
    _ => throw ArgumentError.value(entry.section, 'section'),
  };

  Widget _facilities() => _listing<DemoPan>(
    'wajan',
    settings.pans,
    title: (item) => item.value.name,
    summary: (item) => 'Kapasitas ${item.value.capacity} L',
    fields: (item) => [
      SettingsField(
        'Nama wajan',
        initial: item?.value.name ?? '',
        validator: (name) =>
            _unique(settings.pans, item, name, (pan) => pan.name),
      ),
      SettingsField(
        'Kapasitas',
        initial: item?.value.capacity ?? '',
        suffix: 'L',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: validatePositiveDecimal,
      ),
    ],
    toValue: (values) =>
        (name: values['Nama wajan']!, capacity: values['Kapasitas']!),
  );

  Widget _operators() => _listing<DemoOperator>(
    'operator',
    settings.operators,
    title: (item) => item.value.name,
    summary: (item) => '${item.value.phone}\n${item.value.assignment}',
    notes: const [SettingsNote('Gunakan nama dan nomor sintetis untuk demo.')],
    fields: (item) => [
      SettingsField('Nama operator', initial: item?.value.name ?? ''),
      SettingsField(
        'Nomor WhatsApp',
        initial: item?.value.phone ?? '',
        hint: '+6280000000000',
        keyboardType: TextInputType.phone,
        validator: (phone) {
          if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) {
            return 'Gunakan format internasional seperti +62.';
          }
          return _unique(
            settings.operators,
            item,
            phone,
            (operator) => operator.phone,
          );
        },
      ),
      SettingsField('Penugasan', initial: item?.value.assignment ?? ''),
    ],
    toValue: (values) => (
      name: values['Nama operator']!,
      phone: values['Nomor WhatsApp']!,
      assignment: values['Penugasan']!,
    ),
    confirmation: (item, values) => _disables(item, values)
        ? 'Nonaktifkan ${item!.value.name} pada daftar operator demo?'
        : null,
  );

  Widget _shifts() => _listing<DemoShift>(
    'shift',
    settings.shifts,
    title: (item) => item.value.name,
    summary: (item) {
      final shift = item.value;
      final nextDay = shift.end.compareTo(shift.start) < 0
          ? ' · Hari berikutnya'
          : '';
      return '${shift.start}–${shift.end}$nextDay';
    },
    fields: (item) => [
      SettingsField(
        'Nama sesi',
        initial: item?.value.name ?? '',
        validator: (name) =>
            _unique(settings.shifts, item, name, (shift) => shift.name),
      ),
      SettingsField(
        'Jam mulai',
        initial: item?.value.start ?? '',
        hint: '07:00',
        keyboardType: TextInputType.datetime,
        validator: _validateTime,
      ),
      SettingsField(
        'Jam selesai',
        initial: item?.value.end ?? '',
        hint: '15:00',
        keyboardType: TextInputType.datetime,
        validator: _validateTime,
      ),
    ],
    validateForm: (values) => values['Jam mulai'] == values['Jam selesai']
        ? 'Jam selesai harus berbeda dari jam mulai.'
        : null,
    toValue: (values) => (
      name: values['Nama sesi']!,
      start: values['Jam mulai']!,
      end: values['Jam selesai']!,
    ),
  );

  Widget _accounts() => _listing<DemoAccount>(
    'akun',
    settings.accounts,
    title: (item) => item.id == SettingsDemo.currentAccountId
        ? '${item.value.name} (akun ini)'
        : item.value.name,
    summary: (item) => '${item.value.role.label}\n${item.value.email}',
    notes: const [
      SettingsNote('Gunakan alamat email sintetis untuk demo.'),
      SizedBox(height: 8),
      SettingsNote(
        'Admin meninjau laporan dan mengelola konfigurasi pabrik. '
        'Owner/Manager juga mengelola akun admin, analitik, dan ekspor.',
      ),
    ],
    fields: (item) => [
      SettingsField('Nama pengguna', initial: item?.value.name ?? ''),
      SettingsField(
        'Email',
        initial: item?.value.email ?? '',
        keyboardType: TextInputType.emailAddress,
        validator: (email) {
          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
            return 'Masukkan alamat email yang valid.';
          }
          return _unique(
            settings.accounts,
            item,
            email,
            (account) => account.email,
          );
        },
      ),
      SettingsField(
        'Peran',
        initial: item?.value.role.label ?? DemoRole.admin.label,
        options: DemoRole.values.map((role) => role.label).toList(),
        readOnly: item?.id == SettingsDemo.currentAccountId,
      ),
    ],
    lockedStatus: (item) => item?.id == SettingsDemo.currentAccountId,
    toValue: (values) => (
      name: values['Nama pengguna']!,
      email: values['Email']!,
      role: DemoRole.values.firstWhere((role) => role.label == values['Peran']),
    ),
    confirmation: (item, values) {
      if (item == null) return null;
      final roleChanged = item.value.role.label != values['Peran'];
      final disabled = _disables(item, values);
      if (roleChanged && disabled) {
        return 'Ubah peran ${item.value.name} menjadi ${values['Peran']} '
            'dan nonaktifkan akun demo ini?';
      }
      if (roleChanged) {
        return 'Ubah peran ${item.value.name} menjadi ${values['Peran']}?';
      }
      if (disabled) return 'Nonaktifkan akun demo ${item.value.name}?';
      return null;
    },
  );

  Widget _grades(BuildContext context) => _listing<DemoGrade>(
    'grade',
    settings.grades,
    title: (item) => item.value.name,
    summary: (item) {
      final price = settings.priceFor(item.id);
      return 'Kode ${item.value.code} · ${price == null ? 'Harga belum diatur' : 'Rp$price/kg'}';
    },
    notes: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  HargaBiayaPage(settings: settings, onNavigate: onNavigate),
            ),
          ),
          child: const Text('Atur harga per grade'),
        ),
      ),
    ],
    fields: (item) => [
      SettingsField('Nama grade', initial: item?.value.name ?? ''),
      SettingsField(
        'Kode grade',
        initial: item?.value.code ?? '',
        validator: (code) =>
            _unique(settings.grades, item, code, (grade) => grade.code),
      ),
    ],
    toValue: (values) => (
      name: values['Nama grade']!,
      code: values['Kode grade']!.toUpperCase(),
    ),
  );

  Widget _additives() => _listing<DemoAdditive>(
    'bahan',
    settings.additives,
    title: (item) => item.value.name,
    summary: (item) {
      final additive = item.value;
      return '${additive.unit} · ${additive.amount.isEmpty ? 'Takaran belum diatur' : additive.amount}';
    },
    notes: const [SettingsNote('Catat gamping dalam bentuk takaran aslinya.')],
    fields: (item) => [
      SettingsField(
        'Nama bahan',
        initial: item?.value.name ?? '',
        validator: (name) => _unique(
          settings.additives,
          item,
          name,
          (additive) => additive.name,
        ),
      ),
      SettingsField(
        'Satuan',
        initial: item?.value.unit ?? '',
        hint: 'Takaran asli',
      ),
      SettingsField(
        'Takaran',
        initial: item?.value.amount ?? '',
        hint: 'Contoh 1½ gayung',
        optional: true,
      ),
    ],
    toValue: (values) => (
      name: values['Nama bahan']!,
      unit: values['Satuan']!,
      amount: values['Takaran']!,
    ),
  );

  Widget _listing<T>(
    String itemLabel,
    List<DemoItem<T>> items, {
    required String Function(DemoItem<T>) title,
    required String Function(DemoItem<T>) summary,
    required List<SettingsField> Function(DemoItem<T>?) fields,
    required T Function(Map<String, String>) toValue,
    List<Widget> notes = const [],
    bool Function(DemoItem<T>?)? lockedStatus,
    String? Function(DemoItem<T>?, Map<String, String>)? confirmation,
    String? Function(Map<String, String>)? validateForm,
  }) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      Future<void> edit(DemoItem<T>? item) async {
        final values = await showSettingsEditor(
          context,
          title: item == null ? 'Tambah $itemLabel' : 'Edit $itemLabel',
          fields: [
            ...fields(item),
            SettingsField(
              _status,
              initial: item?.active == false ? _inactive : _active,
              options: const [_active, _inactive],
              readOnly: lockedStatus?.call(item) ?? false,
            ),
          ],
          confirmation: (values) => confirmation?.call(item, values),
          validateForm: validateForm,
        );
        if (values == null || !context.mounted) return;
        settings.saveItem(
          items,
          item,
          toValue(values),
          active: values[_status] == _active,
        );
        showSettingsSaved(context);
      }

      return SettingsPageFrame(
        title: entry.title,
        subtitle: entry.subtitle,
        onNavigate: onNavigate,
        children: [
          ...notes,
          if (notes.isNotEmpty) const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => edit(null),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Tambah $itemLabel'),
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty) SettingsNote('Belum ada $itemLabel.'),
          for (final item in items) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                title(item),
                style: niraText(NiraType.section, weight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${summary(item)}\n${item.active ? _active : _inactive}',
                  style: niraText(
                    NiraType.caption,
                    color: niraLeaf,
                    height: 1.4,
                  ),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, color: niraGreen),
              onTap: () => edit(item),
            ),
            const Divider(height: 1, color: niraLine),
          ],
        ],
      );
    },
  );
}

bool _disables<T>(DemoItem<T>? item, Map<String, String> values) =>
    item?.active == true && values[_status] == _inactive;

String? _unique<T>(
  List<DemoItem<T>> items,
  DemoItem<T>? previous,
  String value,
  String Function(T) keyOf,
) =>
    items.any(
      (item) =>
          item.id != previous?.id &&
          keyOf(item.value).toLowerCase() == value.toLowerCase(),
    )
    ? 'Nilai ini sudah digunakan.'
    : null;

String? _validateTime(String value) =>
    RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)
    ? null
    : 'Gunakan format JJ:MM.';
