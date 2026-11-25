import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/nira_loading.dart';
import '../pekerjaan/review_api.dart';
import 'settings_demo.dart';
import 'settings_widgets.dart';

class ConnectedSettingsPage extends StatefulWidget {
  const ConnectedSettingsPage({
    required this.entry,
    required this.api,
    required this.scope,
    required this.synthetic,
    required this.onNavigate,
    super.key,
  });

  final SettingEntry entry;
  final ReviewApi api;
  final FactoryScope scope;
  final bool synthetic;
  final ValueChanged<NiraTab> onNavigate;

  @override
  State<ConnectedSettingsPage> createState() => _ConnectedSettingsPageState();
}

class _ConnectedSettingsPageState extends State<ConnectedSettingsPage> {
  late Future<List<Widget>> _content = _load();
  bool _saving = false;

  Future<void> _save(
    Future<Json> Function() action,
    String Function(Json) notice,
  ) async {
    if (_saving) return;
    _saving = true;
    try {
      final result = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice(result))));
      setState(() => _content = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ReviewApiError
                  ? error.detail ?? error.message
                  : 'Pengaturan gagal disimpan.',
            ),
          ),
        );
        setState(() => _content = _load());
      }
    } finally {
      _saving = false;
    }
  }

  Future<void> _profile(Json factory) async {
    if (_saving) return;
    final values = await showSettingsEditor(
      context,
      title: 'Edit profil pabrik',
      fields: [
        SettingsField(
          'Kode pabrik',
          initial: factory['displayCode'] as String? ?? '',
          optional: true,
        ),
        SettingsField(
          'Cabang',
          initial: factory['branchName'] as String? ?? '',
          optional: true,
        ),
        SettingsField(
          'WhatsApp bantuan',
          initial: factory['supportPhone'] as String? ?? '',
          optional: true,
          keyboardType: TextInputType.phone,
          hint: '+62…',
          validator: (value) => RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)
              ? null
              : 'Pakai format internasional, misalnya +62…',
        ),
      ],
    );
    if (values == null || !mounted) return;
    String? optional(String key) {
      final value = values[key]!.trim();
      return value.isEmpty ? null : value;
    }

    await _save(
      () => widget.api.writeProduction(widget.scope.basePath, {
        'version': factory['version'],
        'displayCode': optional('Kode pabrik'),
        'branchName': optional('Cabang'),
        'supportPhone': optional('WhatsApp bantuan'),
      }, id: 'profile'),
      (_) => 'Profil pabrik diperbarui.',
    );
  }

  Future<void> _inviteAdmin() async {
    if (_saving) return;
    final values = await showSettingsEditor(
      context,
      title: 'Tambahkan admin pabrik',
      fields: [
        SettingsField(
          'Email admin',
          keyboardType: TextInputType.emailAddress,
          validator: (value) =>
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
              ? null
              : 'Periksa email admin.',
        ),
      ],
      confirmation: (value) =>
          'Berikan akses admin pabrik ini kepada ${value['Email admin']}?',
    );
    if (values == null || !mounted) return;
    await _save(
      () => widget.api.writeProduction(
        [...widget.scope.basePath, 'memberships', 'admin'],
        {'email': values['Email admin']},
      ),
      (result) => result['inviteSent'] == true
          ? 'Undangan admin dikirim.'
          : 'Akun mendapat akses admin pabrik.',
    );
  }

  Future<void> _setAdminActive(Json member, bool active) async {
    if (_saving) return;
    final confirmed = await confirmSettingsChange(
      context,
      active
          ? 'Aktifkan kembali akses admin ini?'
          : 'Nonaktifkan akses admin ini pada pabrik ini?',
    );
    if (!confirmed || !mounted) return;
    await _save(
      () => widget.api.writeProduction(
        [...widget.scope.basePath, 'memberships'],
        {'isActive': active},
        id: member['userId'] as String,
      ),
      (_) => active ? 'Akses admin diaktifkan.' : 'Akses admin dinonaktifkan.',
    );
  }

  Future<List<Widget>> _load() async {
    final scope = widget.scope;
    final api = widget.api;
    switch (widget.entry.section) {
      case SettingSection.identity:
        final factory = await api.getProduction(scope.basePath);
        return [
          _factoryCard(factory['name'] as String),
          const SizedBox(height: NiraSpace.md),
          _group([
            SettingsInfoRow(
              icon: Icons.apartment_outlined,
              title: 'Tenant',
              description: scope.tenantName,
            ),
            SettingsInfoRow(
              icon: Icons.verified_user_outlined,
              title: 'Peran Anda',
              description: _role(factory['role']),
            ),
            for (final (key, title, icon) in const [
              ('displayCode', 'Kode pabrik', Icons.tag),
              ('branchName', 'Cabang', Icons.place_outlined),
              ('supportPhone', 'WhatsApp bantuan', Icons.support_agent),
            ])
              if (factory[key] case final String value)
                SettingsInfoRow(icon: icon, title: title, description: value),
          ]),
          if (factory['role'] == 'owner' && factory['version'] is int)
            TextButton(
              onPressed: () => _profile(factory),
              child: const Text('Edit profil pabrik'),
            ),
        ];
      case SettingSection.access:
        if (scope.role != 'owner') throw const ReviewApiError(403);
        final data = await api.getProduction([
          ...scope.basePath,
          'memberships',
        ]);
        final members = (data['memberships'] as List).cast<Json>();
        return [
          OutlinedButton(
            onPressed: _inviteAdmin,
            child: const Text('Tambahkan admin'),
          ),
          if (members.isEmpty)
            const SettingsMessage(
              icon: Icons.people_outline,
              message: 'Belum ada anggota tercatat.',
            )
          else
            _group([
              for (final member in members)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsInfoRow(
                      icon: Icons.person_outline,
                      title: _role(member['role']),
                      description:
                          member['email'] as String? ??
                          'ID akun ${member['userId'] as String}',
                      status: _status(member['isActive'] as bool),
                    ),
                    if (member['role'] == 'admin')
                      TextButton(
                        onPressed: () =>
                            _setAdminActive(member, member['isActive'] != true),
                        child: Text(
                          member['isActive'] == true
                              ? 'Nonaktifkan admin'
                              : 'Aktifkan admin',
                        ),
                      ),
                  ],
                ),
            ]),
        ];
      case SettingSection.facilities:
        final report = await api.productionReport(
          scope,
          synthetic: widget.synthetic,
        );
        final batchesByWok = <int, int>{};
        for (final lot in (report['items'] as List).cast<Json>()) {
          for (final batch in (lot['batches'] as List).cast<Json>()) {
            final wok = batch['wokNumber'] as int;
            batchesByWok.update(wok, (count) => count + 1, ifAbsent: () => 1);
          }
        }
        final woks = batchesByWok.keys.toList()..sort();
        return [
          if (woks.isEmpty)
            const SettingsMessage(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Riwayat pemakaian wajan',
              message: 'Belum ada wajan pada batch sah.',
            )
          else ...[
            const SettingsMessage(
              icon: Icons.history,
              title: 'Riwayat pemakaian wajan',
              message: 'Wajan tercatat di produksi berdasarkan batch sah.',
            ),
            const SizedBox(height: NiraSpace.md),
            _group([
              for (final number in woks)
                SettingsInfoRow(
                  icon: Icons.precision_manufacturing_outlined,
                  title: 'Wajan $number',
                  description: '${batchesByWok[number]} batch disahkan',
                ),
            ]),
          ],
        ];
      case SettingSection.grades:
        return [
          SettingsPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Klasifikasi hasil produksi',
                  style: niraText(NiraType.section, weight: FontWeight.w700),
                ),
                const SizedBox(height: NiraSpace.xs),
                Text(
                  'Gunakan satu grade untuk setiap batch.',
                  style: niraText(NiraType.body, color: niraLeaf),
                ),
                const SizedBox(height: NiraSpace.lg),
                Wrap(
                  spacing: NiraSpace.sm,
                  runSpacing: NiraSpace.sm,
                  children: [
                    for (final grade in defaultGradeCodes)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: niraGreen.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(niraRadius),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(NiraSpace.md),
                          child: Text(
                            'Grade $grade',
                            style: niraText(
                              NiraType.body,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ];
      case SettingSection.shifts:
        return const [
          SettingsPanel(
            child: SettingsInfoRow(
              icon: Icons.schedule_outlined,
              title: 'Pencatatan sif',
              description: 'Sif dicatat pada kolom Sif di Nota Produksi.',
            ),
          ),
          SizedBox(height: NiraSpace.md),
          SettingsMessage(
            icon: Icons.calendar_today_outlined,
            title: 'Jadwal pabrik',
            message: 'Jadwal sif per pabrik belum tersedia.',
          ),
        ];
      case SettingSection.rules:
        return [
          _group(const [
            SettingsInfoRow(
              icon: Icons.label_outline,
              title: 'Grade hasil',
              description: 'Satu grade dicatat untuk setiap batch.',
            ),
            SettingsInfoRow(
              icon: Icons.water_drop_outlined,
              title: 'Nira campuran',
              description: 'Catat volume nira dari setiap kloter asal.',
            ),
            SettingsInfoRow(
              icon: Icons.scale_outlined,
              title: 'Isi dan hasil',
              description: 'Kolom ISI dan HASIL pada Nota Produksi memakai kg.',
            ),
          ]),
          const SizedBox(height: NiraSpace.md),
          const SettingsMessage(
            icon: Icons.pending_outlined,
            title: 'Menunggu konfirmasi',
            message:
                'Kapasitas yang berlaku, konversi kg ke liter, dan dampak masak ulang pada kapasitas dan nilai.',
            pending: true,
          ),
        ];
      case SettingSection.additives:
        return const [
          SettingsPanel(
            child: SettingsInfoRow(
              icon: Icons.science_outlined,
              title: 'Gamping',
              description:
                  'Catat pada kolom Gamping di Nota Produksi dengan takaran aslinya.',
            ),
          ),
          SizedBox(height: NiraSpace.md),
          SettingsMessage(
            icon: Icons.list_alt_outlined,
            title: 'Daftar bahan',
            message: 'Daftar BTP per pabrik belum tersedia.',
          ),
        ];
      case SettingSection.operators:
      case SettingSection.forms:
      case SettingSection.prices:
        throw StateError('Halaman memiliki rute Pengaturan sendiri.');
    }
  }

  Widget _group(List<Widget> rows) => SettingsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const Divider(height: NiraSpace.xl, color: niraLine),
          rows[index],
        ],
      ],
    ),
  );

  Widget _factoryCard(String name) => DecoratedBox(
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(niraRadius * 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(NiraSpace.lg),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.factory_outlined, color: niraYellow, size: 32),
          ),
          const SizedBox(width: NiraSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nama pabrik',
                  style: niraText(NiraType.body, color: Colors.white),
                ),
                const SizedBox(height: NiraSpace.xs),
                Text(
                  name,
                  style: niraText(
                    NiraType.metric,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _status(bool active) => DecoratedBox(
    decoration: BoxDecoration(
      color: active
          ? niraGreen.withValues(alpha: .09)
          : niraLine.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(niraRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NiraSpace.sm,
        vertical: NiraSpace.xs,
      ),
      child: Text(
        active ? 'Aktif' : 'Nonaktif',
        style: niraText(NiraType.caption, weight: FontWeight.w700),
      ),
    ),
  );

  String _role(Object? role) => switch (role) {
    'owner' => 'Pemilik',
    'admin' => 'Admin',
    _ => throw const FormatException('Peran akun tidak dikenali.'),
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Widget>>(
    future: _content,
    builder: (context, snapshot) {
      final history = widget.entry.section == SettingSection.facilities;
      return SettingsPageFrame(
        title: widget.entry.title,
        keepTitleVisible: true,
        subtitle: widget.entry.section == SettingSection.identity
            ? null
            : [
                widget.scope.factoryName,
                if (history) 'Semua tanggal',
                if (history && widget.synthetic) 'Data sintetis',
              ].join(' · '),
        onNavigate: widget.onNavigate,
        children: [
          if (snapshot.connectionState != ConnectionState.done)
            const NiraLoading(label: 'Memuat pengaturan…')
          else if (snapshot.hasError)
            SettingsLoadError(
              accessDenied: switch (snapshot.error) {
                ReviewApiError(status: 403) => true,
                _ => false,
              },
              message: 'Data pengaturan belum bisa dimuat.',
              onRetry: () => setState(() {
                _content = _load();
              }),
            )
          else
            ...snapshot.requireData,
        ],
      );
    },
  );
}
