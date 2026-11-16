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
  ];

  final marginRows = const [
    AnalyticsRow('Sugeng', 'MJT-260926-1A', 'Rp570.000', '', day: 20),
    AnalyticsRow('Slamet', 'MJT-260926-2A', 'Rp230.000', '', day: 20),
    AnalyticsRow('Darto', 'MJT-260926-3A', 'Rp1.140.000', '', day: 20),
    AnalyticsRow('Mulyanto', 'MJT-250926-1A', 'Rp430.000', '', day: 19),
    AnalyticsRow('Masud', 'MJT-250926-2A', 'Rp800.000', '', day: 19),
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

  List<AnalyticsRow> get visibleRows {
    final normalized = query.trim().toLowerCase();
    final rows = tab == ReportTab.margin ? marginRows : rendemenRows;
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
