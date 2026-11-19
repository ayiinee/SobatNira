import 'package:flutter/material.dart';

import '../kloter/kloter_date_filter.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';

Future<void> filterConnectedReport(
  BuildContext context,
  ConnectedReports reports,
) async {
  final result = await showKloterDateFilter(
    context,
    reports.filter,
    today: DateTime.now(),
  );
  if (result != null) await reports.setFilter(result.selection);
}

class ConnectedReportStatus extends StatelessWidget {
  const ConnectedReportStatus({required this.reports, super.key});
  final ConnectedReports reports;
  @override
  Widget build(BuildContext context) {
    if (reports.loading) {
      return const LinearProgressIndicator();
    }
    if (reports.error != null) {
      return Column(
        children: [
          Text(
            reports.error is ReviewApiError
                ? (reports.error as ReviewApiError).message
                : 'Laporan gagal dimuat.',
          ),
          TextButton(
            onPressed: reports.refresh,
            child: const Text('Coba lagi memuat laporan'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
