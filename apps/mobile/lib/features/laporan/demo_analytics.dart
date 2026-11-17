import 'package:flutter/foundation.dart';

import '../kloter/kloter_date_filter.dart';

enum ReportTab { production, margin }

enum ProductionVariant { rendemen, gulaFinal, grade }

class DemoAnalytics extends ChangeNotifier {
  ReportTab tab = ReportTab.production;
  ProductionVariant variant = ProductionVariant.rendemen;
  String query = '';
  KloterDateFilter? dateFilter;

  final rendemenRows = const [
    AnalyticsRow('Sugeng', 'MJT-260926-1A', '90Kg', '6,0%', day: 20),
    AnalyticsRow('Slamet', 'MJT-260926-2A', '90Kg', '6,0%', day: 20),
    AnalyticsRow('Darto', 'MJT-260926-3A', '90Kg', '6,0%', day: 20),
    AnalyticsRow('Mulyanto', 'MJT-250926-1A', '90Kg', '6,0%', day: 19),
    AnalyticsRow('Masud', 'MJT-250926-2A', '90Kg', '6,0%', day: 19),
    AnalyticsRow('Salim', 'MJT-240926-1A', '90Kg', '6,0%', day: 18),
    AnalyticsRow('Mawarji', 'MJT-240926-2A', '90Kg', '6,0%', day: 18),
    AnalyticsRow('Hadi', 'MJT-230926-1A', '85Kg', '5,8%', day: 17),
    AnalyticsRow('Joko', 'MJT-230926-2A', '95Kg', '6,3%', day: 17),
    AnalyticsRow('Wahyu', 'MJT-220926-1A', '80Kg', '5,5%', day: 16),
    AnalyticsRow('Budi', 'MJT-220926-2A', '100Kg', '6,7%', day: 16),
    AnalyticsRow('Rini', 'MJT-210926-1A', '88Kg', '5,9%', day: 15),
  ];

  final marginRows = const [
    AnalyticsRow('Sugeng', 'MJT-260926-1A', 'Rp570.000', '', day: 20),
    AnalyticsRow('Slamet', 'MJT-260926-2A', 'Rp230.000', '', day: 20),
    AnalyticsRow('Darto', 'MJT-260926-3A', 'Rp1.140.000', '', day: 20),
    AnalyticsRow('Mulyanto', 'MJT-250926-1A', 'Rp430.000', '', day: 19),
    AnalyticsRow('Masud', 'MJT-250926-2A', 'Rp800.000', '', day: 19),
    AnalyticsRow('Hadi', 'MJT-230926-1A', 'Rp670.000', '', day: 17),
    AnalyticsRow('Joko', 'MJT-230926-2A', 'Rp350.000', '', day: 17),
    AnalyticsRow('Wahyu', 'MJT-220926-1A', 'Rp900.000', '', day: 16),
    AnalyticsRow('Budi', 'MJT-220926-2A', 'Rp420.000', '', day: 16),
    AnalyticsRow('Rini', 'MJT-210926-1A', 'Rp780.000', '', day: 15),
  ];

  void setTab(ReportTab value) {
    if (tab == value) return;
    tab = value;
    notifyListeners();
  }

  void setVariant(ProductionVariant value) {
    if (variant == value) return;
    variant = value;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setDateFilter(KloterDateFilter? value) {
    dateFilter = value;
    notifyListeners();
  }

  List<AnalyticsRow> get visibleRows => rowsFor(tab);

  List<AnalyticsRow> rowsFor(ReportTab reportTab) {
    final normalized = query.trim().toLowerCase();
    final rows = reportTab == ReportTab.margin ? marginRows : rendemenRows;
    return rows.where((row) {
      return (dateFilter?.contains(DateTime(2026, 10, row.day)) ?? true) &&
          (normalized.isEmpty ||
              row.supplier.toLowerCase().contains(normalized) ||
              row.code.toLowerCase().contains(normalized));
    }).toList();
  }
}

class AnalyticsRow {
  const AnalyticsRow(
    this.supplier,
    this.code,
    this.value,
    this.secondary, {
    this.day = 20,
  });

  final String supplier;
  final String code;
  final String value;
  final String secondary;
  final int day;
}
