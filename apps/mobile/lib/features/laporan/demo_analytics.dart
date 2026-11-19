import 'package:flutter/foundation.dart';

import '../kloter/kloter_date_filter.dart';
import '../kloter/demo_lot_fixture.dart';

enum ReportTab { production, margin }

enum ProductionVariant { rendemen, gulaFinal, grade }

class DemoAnalytics extends ChangeNotifier {
  ReportTab tab = ReportTab.production;
  ProductionVariant variant = ProductionVariant.rendemen;
  String query = '';
  KloterDateFilter? dateFilter;

  final rendemenRows = [
    _row('MJT-260926-1A', false),
    _row('MJT-260926-2A', false),
    _row('MJT-260926-3A', false),
    _row('MJT-250926-1A', false),
    _row('MJT-250926-2A', false),
    _row('MJT-240926-1A', false),
    _row('MJT-240926-2A', false),
    _row('MJT-230926-1A', false),
    _row('MJT-230926-2A', false),
    _row('MJT-220926-1A', false),
    _row('MJT-220926-2A', false),
    _row('MJT-210926-1A', false),
  ];

  final marginRows = [
    _row('MJT-260926-1A', true),
    _row('MJT-260926-2A', true),
    _row('MJT-260926-3A', true),
    _row('MJT-250926-1A', true),
    _row('MJT-250926-2A', true),
    _row('MJT-230926-1A', true),
    _row('MJT-230926-2A', true),
    _row('MJT-220926-1A', true),
    _row('MJT-220926-2A', true),
    _row('MJT-210926-1A', true),
  ];

  AnalyticsRow? selectedRow;
  static AnalyticsRow _row(String code, bool margin) {
    final lot = demoLotFor(code);
    return AnalyticsRow(
      lot.supplier,
      code,
      margin ? demoMoney(lot.marginRupiah) : '${lot.sugarKg}Kg',
      margin
          ? ''
          : '${demoNumber(lot.sugarKg / lot.caneKg * 100, decimals: 1)}%',
      day: lot.day,
    );
  }

  List<DemoLotFixture> get visibleLots =>
      rowsFor(ReportTab.production).map((row) => demoLotFor(row.code)).toList();
  int get sugarTotal => visibleLots.fold(0, (sum, lot) => sum + lot.sugarKg);
  int get caneTotal => visibleLots.fold(0, (sum, lot) => sum + lot.caneKg);
  int get marginTotal => rowsFor(
    ReportTab.margin,
  ).fold(0, (sum, row) => sum + demoLotFor(row.code).marginRupiah);
  int get valueTotal => rowsFor(
    ReportTab.margin,
  ).fold(0, (sum, row) => sum + demoLotFor(row.code).productionValue);
  int get costTotal => valueTotal - marginTotal;
  int gradeWeight(String grade) {
    var result = 0;
    for (final lot in visibleLots) {
      for (var i = 0; i < lot.batchCount; i++) {
        if (['A', 'B', 'C'][i % 3] == grade) result += lot.batchWeights[i];
      }
    }
    return result;
  }

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
    this.date,
    this.id,
  });

  final String supplier;
  final String code;
  final String value;
  final String secondary;
  final int day;
  final DateTime? date;
  final String? id;
  DateTime get occurredDate => date ?? DateTime(2026, 10, day);
}
