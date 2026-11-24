import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_detail_widgets.dart';

class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    required this.title,
    required this.onNavigate,
    required this.children,
    this.subtitle,
    this.bottomAction,
    this.tab = NiraTab.pengaturan,
    this.hideNavigationWhileEditing = false,
    this.keepTitleVisible = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final ValueChanged<NiraTab> onNavigate;
  final List<Widget> children;
  final Widget? bottomAction;
  final NiraTab tab;
  final bool hideNavigationWhileEditing;
  final bool keepTitleVisible;

  @override
  Widget build(BuildContext context) {
    final heading = DetailTitle(title);
    final content = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: NiraSpace.sm),
      children: [
        if (!keepTitleVisible) heading,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: niraPageInset(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: NiraSpace.xs),
                  child: Text(
                    subtitle!,
                    style: niraText(
                      keepTitleVisible ? NiraType.body : NiraType.caption,
                      color: niraLeaf,
                    ),
                  ),
                ),
              SizedBox(
                height: keepTitleVisible && subtitle == null
                    ? NiraSpace.xs
                    : NiraSpace.lg,
              ),
              ...children,
            ],
          ),
        ),
      ],
    );
    return NiraScaffold(
      tab: tab,
      hideNavigationWhileEditing: hideNavigationWhileEditing,
      onNavigate: onNavigate,
      bottomAction: bottomAction,
      body: keepTitleVisible
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: NiraSpace.sm),
                  child: heading,
                ),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.child,
    this.padding = const EdgeInsets.all(NiraSpace.lg),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(niraRadius * 1.5)),
      side: BorderSide(color: niraLine),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({
    required this.icon,
    required this.title,
    this.description,
    this.status,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? status;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: niraGreen.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(niraRadius),
          ),
          child: Icon(icon, color: niraGreen, size: 20),
        ),
      ),
      const SizedBox(width: NiraSpace.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: NiraSpace.sm,
              runSpacing: NiraSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: niraText(NiraType.section, weight: FontWeight.w700),
                ),
                ?status,
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: NiraSpace.xs),
              Text(
                description!,
                style: niraText(NiraType.body, color: niraLeaf),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class SettingsMessage extends StatelessWidget {
  const SettingsMessage({
    required this.icon,
    required this.message,
    this.title,
    this.pending = false,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? title;
  final bool pending;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(NiraSpace.lg),
    decoration: BoxDecoration(
      color: pending
          ? niraYellow.withValues(alpha: .17)
          : niraGreen.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(niraRadius * 1.5),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, color: niraGreen, size: 20)),
        const SizedBox(width: NiraSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: niraText(NiraType.body, weight: FontWeight.w700),
                ),
                const SizedBox(height: NiraSpace.xs),
              ],
              Text(message, style: niraText(NiraType.body)),
            ],
          ),
        ),
      ],
    ),
  );
}

class SettingsField {
  const SettingsField(
    this.label, {
    this.initial = '',
    this.options,
    this.validator,
    this.keyboardType,
    this.hint,
    this.prefix,
    this.suffix,
    this.optional = false,
    this.readOnly = false,
  });

  final String label;
  final String initial;
  final List<String>? options;
  final String? Function(String)? validator;
  final TextInputType? keyboardType;
  final String? hint;
  final String? prefix;
  final String? suffix;
  final bool optional;
  final bool readOnly;

  String? validate(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return optional ? null : 'Isi kolom ini.';
    return validator?.call(value);
  }
}

class SettingsForm extends StatefulWidget {
  const SettingsForm({
    required this.fields,
    required this.onSave,
    this.onCancel,
    this.validateForm,
    this.saveLabel = 'Simpan perubahan',
    super.key,
  });

  final List<SettingsField> fields;
  final ValueChanged<Map<String, String>> onSave;
  final VoidCallback? onCancel;
  final String? Function(Map<String, String>)? validateForm;
  final String saveLabel;

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, String>{};
  String? _formError;

  void _save() {
    final form = _formKey.currentState!;
    if (!form.validate()) return;
    form.save();
    final error = widget.validateForm?.call(_values);
    if (error != _formError) setState(() => _formError = error);
    if (error != null) return;
    FocusScope.of(context).unfocus();
    widget.onSave(Map.of(_values));
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in widget.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: _input(field),
          ),
        const SizedBox(height: 3),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _formError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        NiraButton(widget.saveLabel, _save),
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Batal')),
      ],
    ),
  );

  Widget _input(SettingsField field) {
    final decoration = settingsInputDecoration(
      field.label,
      hint: field.hint,
      prefix: field.prefix,
      suffix: field.suffix,
    );
    void save(String? value) => _values[field.label] = value?.trim() ?? '';
    final options = field.options;
    if (options != null) {
      return DropdownButtonFormField<String>(
        key: ValueKey(field.label),
        initialValue: field.initial.isEmpty ? null : field.initial,
        decoration: decoration,
        isExpanded: true,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: field.readOnly ? null : (_) {},
        onSaved: save,
        validator: field.validate,
      );
    }
    return TextFormField(
      key: ValueKey(field.label),
      initialValue: field.initial,
      readOnly: field.readOnly,
      keyboardType: field.keyboardType,
      decoration: decoration,
      validator: field.validate,
      onSaved: save,
    );
  }
}

InputDecoration settingsInputDecoration(
  String label, {
  String? hint,
  String? prefix,
  String? suffix,
}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(niraRadius)),
    borderSide: BorderSide(color: niraGreen),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefix,
    suffixText: suffix,
    filled: true,
    fillColor: Colors.white,
    helperMaxLines: 3,
    errorMaxLines: 3,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: NiraSpace.md,
      vertical: NiraSpace.lg,
    ),
    enabledBorder: border,
    disabledBorder: border.copyWith(
      borderSide: const BorderSide(color: niraLine),
    ),
    border: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: niraGreen, width: 2),
    ),
  );
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: niraText(NiraType.caption, color: niraLeaf));
}

class SettingsLoadError extends StatelessWidget {
  const SettingsLoadError({
    required this.accessDenied,
    required this.message,
    required this.onRetry,
    super.key,
  });

  final bool accessDenied;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsMessage(
        icon: accessDenied ? Icons.lock_outline : Icons.error_outline,
        message: accessDenied
            ? 'Akun ini tidak memiliki akses ke data ini.'
            : message,
      ),
      if (!accessDenied) ...[
        const SizedBox(height: NiraSpace.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ],
    ],
  );
}

void showSettingsSaved(BuildContext context, {String? message}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message ?? 'Perubahan tersimpan selama sesi demo'),
      ),
    );
}

Future<Map<String, String>?> showSettingsEditor(
  BuildContext context, {
  required String title,
  required List<SettingsField> fields,
  String? Function(Map<String, String>)? confirmation,
  String? Function(Map<String, String>)? validateForm,
}) {
  var submitting = false;
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: niraPaper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      constraints: const BoxConstraints(maxWidth: 380),
      scrollable: true,
      title: Text(
        title,
        style: niraText(NiraType.section, weight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 330,
        child: SettingsForm(
          fields: fields,
          validateForm: validateForm,
          onCancel: () => Navigator.pop(dialogContext),
          onSave: (values) async {
            if (submitting) return;
            submitting = true;
            final message = confirmation?.call(values);
            if (message != null) {
              final confirmed = await confirmSettingsChange(
                dialogContext,
                message,
              );
              if (!confirmed || !dialogContext.mounted) {
                submitting = false;
                return;
              }
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext, values);
          },
        ),
      ),
    ),
  );
}

Future<bool> confirmSettingsChange(
  BuildContext context,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: niraPaper,
        title: const Text('Konfirmasi perubahan'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    ) ??
    false;

String? validatePositiveDecimal(String input) {
  final value = double.tryParse(input.replaceAll(',', '.'));
  if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(input) ||
      value == null ||
      !value.isFinite ||
      value <= 0) {
    return 'Masukkan angka lebih dari nol.';
  }
  return null;
}
