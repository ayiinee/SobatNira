import 'package:flutter/material.dart';
import 'connected_lot_pager.dart';

class LotPageFooter extends StatelessWidget {
  const LotPageFooter(this.pager, {super.key});
  final ConnectedLotPager pager;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        if (pager.moreError != null)
          const Text('Halaman berikutnya gagal dimuat.'),
        if (pager.loadingMore)
          const SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(),
          )
        else if (pager.hasMore)
          TextButton(
            onPressed: pager.loadMore,
            child: Text(
              pager.moreError == null
                  ? 'Muat kloter berikutnya'
                  : 'Coba lagi halaman berikutnya',
            ),
          )
        else if (pager.items.isNotEmpty)
          const Text('Semua kloter yang cocok sudah dimuat.'),
      ],
    ),
  );
}
