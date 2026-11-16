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
  final _tab = ValueNotifier(NiraTab.beranda);
  final _pages = <NiraTab, Widget>{};

  Widget _pageFor(NiraTab tab) => _pages.putIfAbsent(
    tab,
    () => switch (tab) {
      NiraTab.beranda => ListenableBuilder(
        listenable: _demo,
        builder: (context, _) =>
            BerandaPage(kloter: _demo.kloter, onOpenKloter: _openKloter),
      ),
      NiraTab.kloter => ListenableBuilder(
        listenable: _demo,
        builder: (context, _) =>
            KloterListPage(kloter: _demo.kloter, onOpenKloter: _openKloter),
      ),
      NiraTab.laporan => LaporanPage(
        analytics: _analytics,
        onOpenDetail: _openReportDetail,
      ),
      NiraTab.pengaturan => PengaturanPage(
        settings: _settings,
        onNavigate: _navigate,
      ),
    },
  );
  @override
  void dispose() {
    _tab.dispose();
    _demo.dispose();
    _analytics.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _navigate(NiraTab tab) {
    final navigator = _navigator.currentState!;
    FocusManager.instance.primaryFocus?.unfocus();
    navigator.popUntil((route) => route.isFirst);
    if (_tab.value == tab) return;
    _tab.value = tab;
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
    theme: niraTheme(),
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFF2F2EE),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child,
        ),
      ),
    ),
    home: _buildHome(),
  );

  Widget _buildHome() => ValueListenableBuilder<NiraTab>(
    valueListenable: _tab,
    builder: (context, tab, _) => NiraScaffold(
      floatingNavigation: true,
      tab: tab,
      onNavigate: _navigate,
      body: IndexedStack(
        index: tab.index,
        children: [
          for (final destination in NiraTab.values)
            TickerMode(
              enabled: destination == tab,
              child: destination == tab || _pages.containsKey(destination)
                  ? _pageFor(destination)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    ),
  );
}
