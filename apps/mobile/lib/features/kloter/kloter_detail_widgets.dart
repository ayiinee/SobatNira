import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../widgets/nira_loading.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/adaptive_value.dart';
import 'demo_production.dart';

const reviewActionHeight = 52.0;
const reviewedActionHeight = 44.0;

class KloterDetailBody extends StatelessWidget {
  const KloterDetailBody({
    required this.section,
    required this.header,
    required this.padding,
    required this.children,
    super.key,
  });

  final int section;
  final List<Widget> header;
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleSize = MediaQuery.textScalerOf(context).scale(NiraType.title);
      if (constraints.maxHeight < 200 + titleSize * 3) {
        return CustomScrollView(
          key: ValueKey(section),
          slivers: [
            SliverList.list(children: header),
            SliverPadding(
              padding: padding,
              sliver: SliverList.list(children: children),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(
            child: ListView(
              key: ValueKey(section),
              padding: padding,
              children: children,
            ),
          ),
        ],
      );
    },
  );
}

class DetailTitle extends StatelessWidget {
  const DetailTitle(this.title, {this.inset, super.key});

  final String title;
  final double? inset;

  @override
  Widget build(BuildContext context) {
    final gutter = inset ?? niraPageInset(context);
    return Padding(
      padding: EdgeInsets.only(left: gutter, right: gutter),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.maybePop(context),
            icon: Transform.translate(
              offset: const Offset(-7, 0),
              child: const Icon(Icons.chevron_left, color: niraGreen, size: 23),
            ),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
              child: Text(
                title,
                style: niraText(NiraType.title, weight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KloterHeading extends StatelessWidget {
  const KloterHeading(this.kloter, {super.key});
  final DemoKloter kloter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: niraPageInset(context)),
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
  const DetailMetrics(
    this.metrics, {
    this.separate = false,
    this.centerAll = false,
    this.singleLineLabels = false,
    super.key,
  });
  final List<(String, String)> metrics;
  final bool separate;
  final bool centerAll;
  final bool singleLineLabels;

  double get _horizontalInset => singleLineLabels ? NiraSpace.xs : NiraSpace.sm;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth =
          MediaQuery.textScalerOf(context).scale(20) *
              (singleLineLabels ? 3.5 : 4.5) +
          _horizontalInset * 2;
      final columns = (constraints.maxWidth / minWidth).floor().clamp(
        1,
        metrics.length,
      );
      final gap = columns < metrics.length || separate ? NiraSpace.md : 1.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      var labelHeight = 0.0;
      for (final metric in metrics) {
        final painter =
            TextPainter(
              text: TextSpan(
                text: metric.$1,
                style: niraText(NiraType.caption, weight: FontWeight.w500),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: singleLineLabels ? 1 : null,
            )..layout(
              maxWidth: (width - _horizontalInset * 2 - 2).clamp(
                1,
                double.infinity,
              ),
            );
        if (painter.height > labelHeight) labelHeight = painter.height;
        painter.dispose();
      }
      final valueHeight = valueTextHeight(
        context,
        niraText(NiraType.title, weight: FontWeight.w700),
      );
      final height =
          (labelHeight + valueHeight + NiraSpace.xs + NiraSpace.sm * 2).clamp(
            60.0,
            double.infinity,
          );
      if (columns < metrics.length) {
        return Wrap(
          spacing: NiraSpace.md,
          runSpacing: NiraSpace.md,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: NiraOutline(
                  _metric(metric, height, labelHeight, center: centerAll),
                ),
              ),
          ],
        );
      }
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0)
              separate
                  ? const SizedBox(width: NiraSpace.md)
                  : SizedBox(
                      height: height,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: NiraSpace.md),
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: niraLine,
                        ),
                      ),
                    ),
            Expanded(
              child: separate
                  ? NiraOutline(
                      _metric(metrics[i], height, labelHeight, center: true),
                    )
                  : _metric(
                      metrics[i],
                      height,
                      labelHeight,
                      center: centerAll || i > 0,
                    ),
            ),
          ],
        ],
      );
      return separate ? row : NiraOutline(row);
    },
  );

  Widget _metric(
    (String, String) metric,
    double height,
    double labelHeight, {
    required bool center,
  }) {
    final label = Text(
      metric.$1,
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: singleLineLabels ? 1 : null,
      softWrap: !singleLineLabels,
      style: niraText(NiraType.caption, weight: FontWeight.w500),
    );
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _horizontalInset,
          vertical: NiraSpace.sm,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: labelHeight,
              child: singleLineLabels
                  ? FittedBox(fit: BoxFit.scaleDown, child: label)
                  : label,
            ),
            const SizedBox(height: NiraSpace.xs),
            NiraValue(
              metric.$2,
              label: metric.$1,
              alignment: center ? Alignment.center : Alignment.centerLeft,
              style: niraText(NiraType.title, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
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
  const DocumentPreview({required this.batch, this.photo, super.key});

  final bool batch;
  final ImageProvider? photo;

  static String asset(bool batch) =>
      'assets/sobatnira/art/nota-${batch ? 'batch' : 'tebu'}.jpg';

  static Future<void> open(
    BuildContext context, {
    required bool batch,
    ImageProvider? photo,
  }) => showDialog<void>(
    context: context,
    builder: (context) => _DocumentViewer(batch: batch, photo: photo),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(niraRadius),
        child: InkWell(
          onTap: () => open(context, batch: batch, photo: photo),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 2.4,
                child: Image(
                  image: photo ?? AssetImage(asset(batch)),
                  fit: BoxFit.cover,
                  semanticLabel: photo == null
                      ? 'Buka pratinjau nota sintetis'
                      : 'Buka pratinjau nota sah',
                ),
              ),
              Positioned(
                top: NiraSpace.xs,
                right: NiraSpace.xs,
                child: IconButton(
                  tooltip: 'Perbesar foto',
                  onPressed: () => open(context, batch: batch, photo: photo),
                  style: IconButton.styleFrom(foregroundColor: Colors.white),
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

class ApprovedDocumentPreview extends StatelessWidget {
  const ApprovedDocumentPreview({
    required this.photo,
    required this.batch,
    required this.fallback,
    super.key,
  });

  final Future<Uint8List?>? photo;
  final bool batch;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: photo,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const AspectRatio(
          aspectRatio: 2.4,
          child: NiraLoading(label: 'Memuat foto nota…', compact: true),
        );
      }
      final bytes = snapshot.data;
      if (bytes == null) {
        return AspectRatio(
          aspectRatio: 2.4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3EF),
              border: Border.all(color: niraLine),
              borderRadius: BorderRadius.circular(niraRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(NiraSpace.sm),
              child: Center(child: fallback),
            ),
          ),
        );
      }
      return DocumentPreview(batch: batch, photo: MemoryImage(bytes));
    },
  );
}

class _DocumentViewer extends StatefulWidget {
  const _DocumentViewer({required this.batch, this.photo});
  final bool batch;
  final ImageProvider? photo;

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
                child: Image(
                  image:
                      widget.photo ??
                      AssetImage(DocumentPreview.asset(widget.batch)),
                  fit: BoxFit.contain,
                  semanticLabel: widget.photo == null
                      ? 'Contoh nota sintetis'
                      : 'Foto nota sah',
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
    this.batchCode,
    required this.label,
    required this.verified,
    required this.onVerify,
    this.enabled = true,
    this.onReopen,
    this.onCorrection,
    this.revalidating = false,
    super.key,
  });
  final int batchNumber;
  final String? batchCode;
  final String label;
  final bool verified;
  final VoidCallback onVerify;
  final bool enabled;
  final VoidCallback? onReopen;
  final VoidCallback? onCorrection;
  final bool revalidating;

  Future<void> _confirm(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final batchTitle = batchCode ?? 'Batch $batchNumber';
    final cancelColor = verified ? colors.error : colors.primary;
    const buttonPadding = EdgeInsets.symmetric(horizontal: NiraSpace.sm);
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: const Color(0x66000000),
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        backgroundColor: niraPaper,
        title: Text(
          verified
              ? 'Batalkan validasi $batchTitle?'
              : revalidating
              ? 'Validasi ulang $batchTitle?'
              : 'Validasi $batchTitle?',
          textAlign: TextAlign.center,
        ),
        content: Text(
          verified
              ? 'Batch kembali ke status Perlu ditinjau dan datanya bisa diedit lagi.'
              : revalidating
              ? 'Hasil koreksi akan dipakai dalam laporan setelah divalidasi.'
              : 'Pastikan data batch sudah benar. Data akan terkunci setelah divalidasi.',
          textAlign: TextAlign.center,
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
    final confirmed = await navigator.push(route);
    // Let the dialog and its scrim finish leaving before the notice slides in.
    await route.completed;
    if (confirmed != true || !context.mounted) return;
    if (verified) {
      onReopen?.call();
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
          verified || !enabled ? null : () => _confirm(context),
          visualDensity: VisualDensity.standard,
          minimumHeight: verified ? reviewedActionHeight : reviewActionHeight,
        ),
      ),
      if (verified && (onReopen != null || onCorrection != null)) ...[
        const SizedBox(width: NiraSpace.sm),
        IconButton.filled(
          tooltip: onCorrection == null
              ? 'Batalkan validasi batch'
              : 'Buka koreksi batch',
          onPressed: onCorrection ?? () => _confirm(context),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(reviewedActionHeight),
            visualDensity: VisualDensity.standard,
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
  const EditableFields({
    required this.fields,
    required this.onEdit,
    this.showEquals = false,
    super.key,
  });

  final List<DemoField> fields;
  final ValueChanged<DemoField>? onEdit;
  final bool showEquals;

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
              if (showEquals) ...[
                Text('=', style: niraText(NiraType.body, color: niraMuted)),
                const SizedBox(width: NiraSpace.sm),
              ],
              Expanded(
                flex: 10,
                child: isDisplayNumber(field.display)
                    ? NiraValue(
                        field.display,
                        label: field.label,
                        abbreviate: false,
                        revealOnTap: onEdit == null,
                        style: niraText(NiraType.body, weight: FontWeight.w600),
                      )
                    : Text(
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
