import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import 'demo_production.dart';

const reviewActionHeight = 52.0;
const reviewedActionHeight = 44.0;

class DetailTitle extends StatelessWidget {
  const DetailTitle(this.title, {this.inset = niraInset, super.key});

  final String title;
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: inset),
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, NiraSpace.md, 0, NiraSpace.md),
          child: Text(
            title,
            style: niraText(NiraType.title, weight: FontWeight.w700),
          ),
        ),
        Positioned(
          left: -18,
          top: 0,
          bottom: 0,
          width: 48,
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.chevron_left, color: niraGreen, size: 23),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
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
        Text(
          kloter.code,
          style: niraText(NiraType.title, weight: FontWeight.w700),
        ),
        const SizedBox(height: NiraSpace.xs),
        Text(kloter.supplier, style: niraText(NiraType.body)),
        const SizedBox(height: NiraSpace.xs),
        Text(formatDate(kloter.date), style: niraText(NiraType.body)),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = MediaQuery.textScalerOf(context).scale(20) * 4.5 + 16;
        final columns = (constraints.maxWidth / minWidth).floor().clamp(
          1,
          metrics.length,
        );
        if (columns < metrics.length) {
          final width =
              (constraints.maxWidth - NiraSpace.md * (columns - 1)) / columns;
          return Wrap(
            spacing: NiraSpace.md,
            runSpacing: NiraSpace.md,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: NiraOutline(_metric(metric, center: false)),
                ),
            ],
          );
        }
        return _row(context);
      },
    );
  }

  Widget _row(BuildContext context) {
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
                  padding: EdgeInsets.symmetric(vertical: NiraSpace.md),
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
          padding: const EdgeInsets.symmetric(
            horizontal: NiraSpace.sm,
            vertical: NiraSpace.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                metric.$1,
                textAlign: center ? TextAlign.center : TextAlign.start,
                style: niraText(NiraType.caption, weight: FontWeight.w500),
              ),
              const SizedBox(height: NiraSpace.xs),
              Text(
                metric.$2,
                textAlign: center ? TextAlign.center : TextAlign.start,
                style: niraText(NiraType.title, weight: FontWeight.w700),
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
      Text(title, style: niraText(NiraType.section, weight: FontWeight.w600));
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
            padding: const EdgeInsets.symmetric(
              horizontal: NiraSpace.sm,
              vertical: NiraSpace.sm,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_rounded,
                  color: niraGreen,
                  size: 32,
                ),
                const SizedBox(width: NiraSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    style: niraText(NiraType.body, weight: FontWeight.w500),
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

  static Future<void> open(BuildContext context, {required bool batch}) =>
      showDialog<void>(
        context: context,
        builder: (context) => _DocumentViewer(batch: batch),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(niraRadius),
        child: InkWell(
          onTap: () => open(context, batch: batch),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 2.4,
                child: Image.asset(
                  asset(batch),
                  fit: BoxFit.cover,
                  semanticLabel: 'Buka pratinjau nota sintetis',
                ),
              ),
              Positioned(
                top: NiraSpace.xs,
                right: NiraSpace.xs,
                child: IconButton(
                  tooltip: 'Perbesar foto',
                  onPressed: () => open(context, batch: batch),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.open_in_full, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _DocumentViewer extends StatefulWidget {
  const _DocumentViewer({required this.batch});
  final bool batch;

  @override
  State<_DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<_DocumentViewer> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      6.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: niraPaper,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: NiraSpace.md,
              right: NiraSpace.xs,
            ),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: 'Tutup nota',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 6,
              trackpadScrollCausesScale: true,
              child: Center(
                child: Image.asset(
                  DocumentPreview.asset(widget.batch),
                  fit: BoxFit.contain,
                  semanticLabel: 'Contoh nota sintetis',
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Perkecil gambar',
                onPressed: () => _zoom(1 / 1.4),
                icon: const Icon(Icons.remove),
              ),
              TextButton(
                onPressed: () => _transform.value = Matrix4.identity(),
                child: const Text('Atur ulang'),
              ),
              IconButton(
                tooltip: 'Perbesar gambar',
                onPressed: () => _zoom(1.4),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: NiraSpace.sm),
        ],
      ),
    ),
  );
}

class BatchReviewActions extends StatelessWidget {
  const BatchReviewActions({
    required this.batchNumber,
    required this.label,
    required this.verified,
    required this.onVerify,
    required this.onReopen,
    super.key,
  });
  final int batchNumber;
  final String label;
  final bool verified;
  final VoidCallback onVerify;
  final VoidCallback onReopen;

  Future<void> _confirm(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final cancelColor = verified ? colors.error : colors.primary;
    const buttonPadding = EdgeInsets.symmetric(horizontal: NiraSpace.sm);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        backgroundColor: niraPaper,
        title: Text(
          verified
              ? 'Batalkan validasi Batch $batchNumber?'
              : 'Validasi Batch $batchNumber?',
          textAlign: TextAlign.center,
        ),
        content: Text(
          verified
              ? 'Batch kembali ke status Perlu ditinjau dan datanya bisa diedit lagi.'
              : 'Pastikan data batch sudah benar. Data akan terkunci setelah divalidasi.',
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: cancelColor,
                    side: BorderSide(color: cancelColor),
                    minimumSize: const Size(0, 48),
                    padding: buttonPadding,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(niraRadius),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal', textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: NiraSpace.sm),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: verified ? colors.error : null,
                    foregroundColor: verified ? Colors.white : null,
                    padding: buttonPadding,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Konfirmasi', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (verified) {
      onReopen();
    } else {
      onVerify();
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: NiraButton(
          label,
          verified ? null : () => _confirm(context),
          visualDensity: VisualDensity.standard,
          minimumHeight: verified ? reviewedActionHeight : reviewActionHeight,
        ),
      ),
      if (verified) ...[
        const SizedBox(width: NiraSpace.sm),
        IconButton.filled(
          tooltip: 'Batalkan validasi batch',
          onPressed: () => _confirm(context),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(reviewedActionHeight),
            iconSize: 20,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(niraRadius),
            ),
          ),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ],
  );
}

class EditableFields extends StatelessWidget {
  const EditableFields({required this.fields, required this.onEdit, super.key});

  final List<DemoField> fields;
  final ValueChanged<DemoField>? onEdit;

  @override
  Widget build(BuildContext context) => NiraOutline(
    Padding(
      padding: const EdgeInsets.all(NiraSpace.xs),
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
    label: onEdit == null ? '${field.label}, terkunci' : 'Edit ${field.label}',
    button: onEdit != null,
    child: InkWell(
      onTap: onEdit == null ? null : () => onEdit!(field),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NiraSpace.md,
            vertical: NiraSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: Text(
                  field.label,
                  style: niraText(
                    NiraType.body,
                    weight: FontWeight.w500,
                    color: const Color(0xFF68736E),
                  ),
                ),
              ),
              const SizedBox(width: NiraSpace.sm),
              Expanded(
                flex: 10,
                child: Text(
                  field.display,
                  style: niraText(NiraType.body, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: NiraSpace.xs),
              Icon(
                onEdit == null ? Icons.lock_outline : Icons.edit_rounded,
                color: niraMuted,
                size: 20,
              ),
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
      style: niraText(NiraType.section, weight: FontWeight.w700),
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
