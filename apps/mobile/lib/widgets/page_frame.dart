import 'package:flutter/material.dart';

import '../sobatnira_ui.dart';

/// The same title, back action and content width used by the demo detail pages.
class NiraPageScaffold extends StatelessWidget {
  const NiraPageScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.onNavigate,
    this.tab = NiraTab.kloter,
    super.key,
  });

  final Widget title, body;
  final List<Widget> actions;
  final ValueChanged<NiraTab>? onNavigate;
  final NiraTab tab;

  @override
  Widget build(BuildContext context) {
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(niraRadius)),
      borderSide: BorderSide(color: niraGreen),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(right: niraPageInset(context)),
          child: Row(
            children: [
              SizedBox(
                width: (niraPageInset(context) - NiraSpace.lg).clamp(
                  0,
                  double.infinity,
                ),
              ),
              IconButton(
                tooltip: 'Kembali',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.chevron_left, size: 23),
              ),
              Expanded(
                child: DefaultTextStyle(
                  style: niraText(NiraType.title, weight: FontWeight.w700),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
                    child: title,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: body,
          ),
        ),
      ],
    );
    final themedContent = Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
          enabledBorder: inputBorder,
          border: inputBorder,
          errorMaxLines: 3,
          helperMaxLines: 3,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: NiraSpace.md,
            vertical: NiraSpace.lg,
          ),
        ),
      ),
      child: content,
    );
    if (onNavigate case final navigate?) {
      return NiraScaffold(tab: tab, onNavigate: navigate, body: themedContent);
    }
    return Scaffold(
      backgroundColor: niraPaper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: niraMaxContentWidth),
            child: themedContent,
          ),
        ),
      ),
    );
  }
}
