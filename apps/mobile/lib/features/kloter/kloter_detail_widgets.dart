import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';

class DetailTitle extends StatelessWidget {
  const DetailTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 18, right: niraInset),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Kembali',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.chevron_left, color: niraGreen, size: 23),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 39),
          visualDensity: VisualDensity.standard,
        ),
        Expanded(
          child: Text(title, style: niraText(17.65, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class KloterHeading extends StatelessWidget {
  const KloterHeading(this.kloter, {super.key});
  final DemoKloter kloter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: niraInset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(kloter.code, style: niraText(20.5, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(kloter.supplier, style: niraText(14.5)),
        const SizedBox(height: 3),
        Text(formatDate(kloter.date), style: niraText(14.5)),
      ],
    ),
  );
}

class DetailMetrics extends StatelessWidget {
  const DetailMetrics(this.metrics, {this.separate = false, super.key});

  final List<(String, String)> metrics;
  final bool separate;

  @override
  Widget build(BuildContext context) {
    if (separate) {
      return Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final metric in metrics)
            Expanded(child: NiraOutline(_metric(metric, center: true))),
        ],
      );
    }
    return NiraOutline(
      IntrinsicHeight(
        child: Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 11),
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: niraLine,
                  ),
                ),
              Expanded(child: _metric(metrics[index], center: index > 0)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric((String, String) metric, {required bool center}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                metric.$1,
                textAlign: center ? TextAlign.center : TextAlign.start,
                style: niraText(11.4, weight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                metric.$2,
                textAlign: center ? TextAlign.center : TextAlign.start,
                style: niraText(21, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
}

class DetailSectionTitle extends StatelessWidget {
  const DetailSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: niraText(15.1, weight: FontWeight.w700));
}

class DocumentLink extends StatelessWidget {
  const DocumentLink(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    onTap: onTap,
    excludeSemantics: true,
    child: NiraOutline(
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 51),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.description_rounded,
                  color: niraGreen,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: niraText(11.4, weight: FontWeight.w500),
                  ),
                ),
                const Icon(Icons.chevron_right, color: niraGreen, size: 17),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class DocumentPreview extends StatelessWidget {
  const DocumentPreview({required this.batch, super.key});

  final bool batch;

  static String asset(bool batch) =>
      'assets/sobatnira/art/nota-${batch ? 'batch' : 'tebu'}.jpg';

  static Future<void> open(
    BuildContext context, {
    required bool batch,
  }) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nota sintetis',
                    style: niraText(17, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Tutup nota',
                  icon: const Icon(Icons.close, color: niraGreen),
                ),
              ],
            ),
            Image.asset(asset(batch), semanticLabel: 'Contoh nota sintetis'),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const DetailSectionTitle('Pratinjau foto'),
      const SizedBox(height: 5),
      Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => open(context, batch: batch),
          child: AspectRatio(
            aspectRatio: 2.4,
            child: Image.asset(
              asset(batch),
              fit: BoxFit.cover,
              semanticLabel: 'Buka pratinjau nota sintetis',
            ),
          ),
        ),
      ),
    ],
  );
}

class EditableFields extends StatelessWidget {
  const EditableFields({required this.fields, required this.onEdit, super.key});

  final List<DemoField> fields;
  final ValueChanged<DemoField> onEdit;

  @override
  Widget build(BuildContext context) => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: [
          for (var index = 0; index < fields.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: niraLine,
              ),
            _field(fields[index]),
          ],
        ],
      ),
    ),
  );

  Widget _field(DemoField field) => Semantics(
    label: 'Edit ${field.label}',
    button: true,
    child: InkWell(
      onTap: () => onEdit(field),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: Text(
                  field.label,
                  style: niraText(
                    11.6,
                    weight: FontWeight.w500,
                    color: const Color(0xFF68736E),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 10,
                child: Text(
                  field.display,
                  style: niraText(11.6, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, color: niraMuted, size: 13),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<String?> editDemoValue(
  BuildContext context, {
  required String label,
  required String initial,
  String? unit,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _EditValueDialog(label: label, initial: initial, unit: unit),
);

class _EditValueDialog extends StatefulWidget {
  const _EditValueDialog({
    required this.label,
    required this.initial,
    this.unit,
  });

  final String label;
  final String initial;
  final String? unit;

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _value.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: niraPaper,
    title: Text(
      'Edit ${widget.label}',
      style: niraText(18, weight: FontWeight.w700),
    ),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _value,
        autofocus: true,
        keyboardType: widget.unit == null
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
        maxLength: 80,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.unit?.trim(),
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        validator: (input) {
          final value = input?.trim() ?? '';
          if (value.isEmpty) return 'Isi nilai terlebih dahulu.';
          if (widget.unit != null &&
              !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(value)) {
            return 'Masukkan angka yang valid.';
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan')),
    ],
  );
}

void verifyDemoReview(
  BuildContext context,
  DemoProduction demo,
  DemoReview review,
) {
  demo.verify(review);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Tersimpan selama sesi demo')));
}
