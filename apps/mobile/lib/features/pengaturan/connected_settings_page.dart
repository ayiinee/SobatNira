import 'production_masters_page.dart';
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
          ]),
        ];
      case SettingSection.access:
        if (scope.role != 'owner') throw const ReviewApiError(403);
        final data = await api.getProduction([
          ...scope.basePath,
          'memberships',
        ]);
        final members = (data['memberships'] as List).cast<Json>();
        return [
          if (members.isEmpty)
            const SettingsMessage(
              icon: Icons.people_outline,
              message: 'Belum ada anggota tercatat.',
            )
          else
            _group([
              for (final member in members)
                SettingsInfoRow(
                  icon: Icons.person_outline,
                  title: _role(member['role']),
                  description: 'ID akun ${member['userId'] as String}',
                  status: _status(member['isActive'] as bool),
                ),
            ]),
        ];
      case SettingSection.facilities:
      case SettingSection.grades:
        return [
          const SettingsMessage(
            icon: Icons.history,
            message: 'Master resmi per pabrik, dengan riwayat versi.',
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ProductionMastersPage(
                  api: api,
                  scope: scope,
                  synthetic: widget.synthetic,
                  kind: widget.entry.section == SettingSection.facilities
                      ? 'wok'
                      : 'grade',
                ),
              ),
            ),
            child: const Text('Kelola master produksi'),
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
            title: 'Pratinjau jadwal pabrik',
            message: 'Jadwal sif per pabrik belum tersedia.',
          ),
        ];
      case SettingSection.rules:
        return [
          _group(const [
            SettingsInfoRow(
              icon: Icons.label_outline,
              title: 'Grade hasil',
              description:
                  'Beberapa grade boleh dicatat. Total berat grade harus sama dengan hasil fisik.',
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
            title: 'Pratinjau daftar bahan',
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
