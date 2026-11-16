import 'package:flutter/material.dart';

import 'features/beranda/beranda_page.dart';
import 'features/kloter/demo_production.dart';
import 'features/kloter/kloter_detail_page.dart';
import 'features/kloter/kloter_list_page.dart';
import 'features/laporan/demo_analytics.dart';
import 'features/laporan/laporan_page.dart';
import 'features/laporan/report_detail_page.dart';
import 'features/pengaturan/pengaturan_page.dart';
import 'features/pengaturan/settings_demo.dart';
import 'sobatnira_ui.dart';

void main() => runApp(const SobatNiraApp());

class SobatNiraApp extends StatefulWidget {
  const SobatNiraApp({super.key});

  @override
  State<SobatNiraApp> createState() => _SobatNiraAppState();
}

class _SobatNiraAppState extends State<SobatNiraApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _demo = DemoProduction();
  final _analytics = DemoAnalytics();
  final _settings = SettingsDemo();
  NiraTab _tab = NiraTab.beranda;
  @override
  void dispose() {
    _demo.dispose();
    _analytics.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _navigate(NiraTab tab) {
    final navigator = _navigator.currentState!;
    FocusManager.instance.primaryFocus?.unfocus();
    navigator.popUntil((route) => route.isFirst);
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  void _openReportDetail(ReportDetailKind kind) {
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailPage(kind: kind, onNavigate: _navigate),
      ),
    );
  }

  void _openKloter(DemoKloter kloter) {
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => KloterDetailPage(
          kloter: kloter,
          demo: _demo,
          onNavigate: _navigate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SobatNira',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    theme: ThemeData(
      fontFamily: 'Inter',
      useMaterial3: true,
      scaffoldBackgroundColor: niraPaper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: niraGreen,
      ).copyWith(primary: niraGreen, surface: niraPaper),
    ),
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFF2F2EE),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child,
        ),
      ),
    ),
    home: NiraScaffold(
      floatingNavigation: true,
      tab: _tab,
      onNavigate: _navigate,
      body: IndexedStack(
        index: _tab.index,
        children: [
          ListenableBuilder(
            listenable: _demo,
            builder: (context, _) =>
                BerandaPage(kloter: _demo.kloter, onOpenKloter: _openKloter),
          ),
          ListenableBuilder(
            listenable: _demo,
            builder: (context, _) =>
                KloterListPage(kloter: _demo.kloter, onOpenKloter: _openKloter),
          ),
          LaporanPage(analytics: _analytics, onOpenDetail: _openReportDetail),
          PengaturanPage(settings: _settings, onNavigate: _navigate),
        ],
      ),
    ),
  );
}
