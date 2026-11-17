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
    super.key,
  });

  final String title;
  final String? subtitle;
  final ValueChanged<NiraTab> onNavigate;
  final List<Widget> children;
  final Widget? bottomAction;
  final NiraTab tab;

  @override
  Widget build(BuildContext context) {
    return NiraScaffold(
      tab: tab,
      onNavigate: onNavigate,
      bottomAction: bottomAction,
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: NiraSpace.sm),
        children: [
          DetailTitle(title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: niraInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle!,
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                  ),
                const SizedBox(height: NiraSpace.lg),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
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
