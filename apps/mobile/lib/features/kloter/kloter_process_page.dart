import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../laporan/connected_reports.dart' show reportNumber;
import '../pekerjaan/review_api.dart';
import 'demo_production.dart';
import 'detail_fields.dart';
import 'juice_volume.dart';
import 'kloter_detail_widgets.dart';

class KloterProcessPage extends StatefulWidget {
  const KloterProcessPage({
    required this.demo,
    required this.kloter,
    required this.onNavigate,
    this.onOpenPekerjaan,
    this.approvedPhoto,
    this.loadStock,
    this.onEdit,
    this.onTransfer,
    this.onClosure,
    super.key,
  });

  final DemoProduction demo;
  final DemoKloter kloter;
  final ValueChanged<NiraTab> onNavigate;
  final VoidCallback? onOpenPekerjaan;
  final Future<Uint8List?> Function(String)? approvedPhoto;
  final Future<Json> Function()? loadStock;
  final Future<bool> Function()? onEdit;
  final Future<void> Function()? onTransfer;
  final Future<void> Function()? onClosure;

  @override
  State<KloterProcessPage> createState() => _KloterProcessPageState();
}

class _KloterProcessPageState extends State<KloterProcessPage> {
  int _selected = 0;
  final _photos = <String, Future<Uint8List?>?>{};
  late Future<Json>? _stock = widget.loadStock?.call();

  Future<void> _edit() async {
    if (await widget.onEdit!() && mounted) Navigator.of(context).pop();
  }

  Future<void> _runStockAction(Future<void> Function() action) async {
    await action();
    if (mounted) _reloadStock();
  }

  void _reloadStock() {
    final stock = widget.loadStock?.call();
    setState(() {
      _stock = stock;
    });
  }

  Widget _stockDetails() => FutureBuilder<Json>(
    future: _stock,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LinearProgressIndicator();
      }
      final stock = snapshot.data;
      if (stock == null) {
        return TextButton(
          onPressed: _reloadStock,
          child: const Text('Coba lagi memuat stok nira'),
        );
      }
      String liters(String key) {
        final value = stock[key];
        return value == null
            ? 'Belum tersedia'
            : '${reportNumber(millilitersToLiters(value.toString()))} L';
      }

      return DetailMetrics([
        ('Stok fisik nira', liters('onHandMl')),
        ('Nira direservasi', liters('reservedMl')),
        ('Nira tersedia', liters('availableMl')),
      ]);
    },
  );

  Future<Uint8List?>? _photo(bool intake) {
    final revision = widget.kloter.noteRevision(intake: intake);
    return revision == null
        ? null
        : _photos.putIfAbsent(
            revision,
            () => widget.approvedPhoto?.call(revision),
          );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.demo,
    builder: (context, _) {
      final kloter = widget.kloter;
      final intake = _selected == 0;
      final connected = kloter.id != null;
      final review = intake ? kloter.intake : kloter.milling;
      final inset = niraPageInset(context);
      return NiraScaffold(
        tab: NiraTab.kloter,
        onNavigate: widget.onNavigate,
        bottomAction: connected
            ? NiraButton('Buka Pekerjaan', widget.onOpenPekerjaan)
            : NiraButton(
                review.verified
                    ? (intake
                          ? 'Tebu masuk terverifikasi'
                          : 'Penggilingan terverifikasi')
                    : (intake
                          ? 'Verifikasi tebu masuk'
                          : 'Verifikasi penggilingan'),
                review.verified
                    ? null
                    : () => verifyDemoReview(context, widget.demo, review),
                visualDensity: VisualDensity.standard,
                minimumHeight: review.verified
                    ? reviewedActionHeight
                    : reviewActionHeight,
              ),
        body: KloterDetailBody(
          section: _selected,
          padding: EdgeInsets.fromLTRB(
            inset,
            NiraSpace.lg,
            inset,
            NiraSpace.sm,
          ),
          header: [
            const DetailTitle('Detail kloter'),
            KloterHeading(kloter),
            const SizedBox(height: 12),
            NiraTabs(
              labels: const ['Tebu masuk', 'Penggilingan'],
              selected: _selected,
              height: 50,
              fontSize: NiraType.body,
              wideIndicator: true,
              inset: 27,
              onSelected: (value) => setState(() => _selected = value),
            ),
          ],
          children: [
            if (connected)
              ApprovedDocumentPreview(
                batch: false,
                photo: _photo(intake),
                fallback: widget.onOpenPekerjaan == null
                    ? const Text('Foto belum tersedia')
                    : DocumentLink(
                        'Foto, bukti, dan revisi di Pekerjaan',
                        widget.onOpenPekerjaan!,
                      ),
              )
            else
              const DocumentPreview(batch: false),
            const SizedBox(height: NiraSpace.xl),
            const DetailSectionTitle('Ringkasan proses'),
            const SizedBox(height: NiraSpace.sm),
            DetailMetrics([
              if (intake) ...[
                (
                  'Tebu bersih',
                  connected && kloter.netWeightKg == null ? '—' : kloter.weight,
                ),
                (
                  'Brix tebu',
                  kloter.brix == null
                      ? '—'
                      : formatQuantity(kloter.brix, '°Bx'),
                ),
              ] else if (connected)
                (
                  'Nira dihasilkan',
                  kloter.juiceLiters == null
                      ? '—'
                      : formatQuantity(kloter.juiceLiters, 'L'),
                )
              else
                (
                  'Nira batch tercatat',
                  formatQuantity(kloter.batchJuiceLiters, 'L'),
                ),
            ]),
            const SizedBox(height: NiraSpace.lg),
            EditableFields(
              fields: detailFields(
                intake ? intakeDetailLabels : millingDetailLabels,
                review.fields,
              ),
              onEdit: connected
                  ? null
                  : (field) async {
                      final value = await editDemoValue(
                        context,
                        label: field.label,
                        initial: field.value,
                      );
                      if (mounted && value != null) {
                        widget.demo.edit(review, field, value);
                      }
                    },
            ),
            if (intake && widget.onEdit != null) ...[
              const SizedBox(height: NiraSpace.md),
              DocumentLink('Edit kloter', _edit),
            ],
            if (!intake && widget.loadStock != null) ...[
              const SizedBox(height: NiraSpace.md),
              _stockDetails(),
              if (widget.onTransfer case final transfer?) ...[
                const SizedBox(height: NiraSpace.sm),
                DocumentLink('Transfer nira', () => _runStockAction(transfer)),
              ],
              if (widget.onClosure case final closure?) ...[
                const SizedBox(height: NiraSpace.sm),
                DocumentLink(
                  'Penutupan dan riwayat',
                  () => _runStockAction(closure),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
