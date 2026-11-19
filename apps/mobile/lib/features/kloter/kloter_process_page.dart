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
      final kloter = widget.kloter;
      final intake = _selected == 0;
      final connected = kloter.id != null;
      final openReview = widget.onOpenPekerjaan;
      final review = intake ? kloter.intake : kloter.milling;
      final inset = niraPageInset(context);
      return NiraScaffold(
        tab: NiraTab.kloter,
        onNavigate: widget.onNavigate,
        bottomAction: connected
            ? openReview == null
                  ? null
                  : NiraButton('Buka Pekerjaan', openReview)
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
            if (connected && openReview != null)
              DocumentLink('Foto, bukti, dan revisi di Pekerjaan', openReview)
            else if (!connected)
              const DocumentPreview(batch: false),
            const SizedBox(height: NiraSpace.xl),
            const DetailSectionTitle('Ringkasan proses'),
            const SizedBox(height: NiraSpace.sm),
            DetailMetrics([
              if (intake) ...[
                ('Tebu bersih', kloter.weight),
                ('Brix tebu', formatQuantity(kloter.brix, '°Bx')),
              ] else if (connected)
                ('Nira dihasilkan', formatQuantity(kloter.juiceLiters, 'L'))
              else
                (
                  'Nira batch tercatat',
                  formatQuantity(kloter.batchJuiceLiters, 'L'),
                ),
            ]),
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
      );
    },
  );
}
