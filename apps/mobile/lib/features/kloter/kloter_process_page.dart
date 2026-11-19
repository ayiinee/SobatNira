import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';
import 'kloter_detail_widgets.dart';

class KloterProcessPage extends StatefulWidget {
  const KloterProcessPage({
    required this.demo,
    required this.kloter,
    required this.onNavigate,
    this.onOpenPekerjaan,
    super.key,
  });

  final DemoProduction demo;
  final DemoKloter kloter;
  final ValueChanged<NiraTab> onNavigate;
  final VoidCallback? onOpenPekerjaan;

  @override
  State<KloterProcessPage> createState() => _KloterProcessPageState();
}

class _KloterProcessPageState extends State<KloterProcessPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.demo,
    builder: (context, _) {
      final intake = _selected == 0;
      final connected = widget.kloter.id != null;
      final review = intake ? widget.kloter.intake : widget.kloter.milling;
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DetailTitle('Detail kloter'),
            KloterHeading(widget.kloter),
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
            Expanded(
              child: ListView(
                key: ValueKey(_selected),
                padding: const EdgeInsets.fromLTRB(
                  niraInset,
                  NiraSpace.lg,
                  niraInset,
                  NiraSpace.sm,
                ),
                children: [
                  if (connected)
                    DocumentLink(
                      'Foto, bukti, dan revisi di Pekerjaan',
                      widget.onOpenPekerjaan!,
                    )
                  else
                    const DocumentPreview(batch: false),
                  const SizedBox(height: NiraSpace.xl),
                  const DetailSectionTitle('Ringkasan proses'),
                  const SizedBox(height: NiraSpace.sm),
                  DetailMetrics(
                    connected
                        ? (intake
                              ? [
                                  ('Tebu bersih', widget.kloter.weight),
                                  (
                                    'Brix tebu',
                                    formatQuantity(widget.kloter.brix, '°Bx'),
                                  ),
                                ]
                              : [
                                  (
                                    'Nira dihasilkan',
                                    formatQuantity(
                                      widget.kloter.juiceLiters,
                                      'L',
                                    ),
                                  ),
                                ])
                        : intake
                        ? const [
                            ('Tebu bersih', '1.500Kg'),
                            ('Brix tebu', '90Kg'),
                          ]
                        : const [('Nira dihasilkan', '360L')],
                  ),
                  const SizedBox(height: NiraSpace.lg),
                  EditableFields(
                    fields: review.fields,
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
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
