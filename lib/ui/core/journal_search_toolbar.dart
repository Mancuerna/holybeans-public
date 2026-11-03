import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/page_layout.dart';

class JournalSearchToolbar extends StatelessWidget {
  const JournalSearchToolbar({
    super.key,
    required this.controller,
    required this.actions,
  });

  final TextEditingController controller;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final search = SearchField(
        label: AppLocalizations.of(context)!.search,
        controller: controller,
        compact: true,
      );
      final buttons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            SizedBox(width: 48, height: 48, child: action),
        ],
      );
      final searchWidth = 160 * MediaQuery.textScalerOf(context).scale(16) / 16;
      if (constraints.maxWidth < searchWidth + actions.length * 48 + 4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 4),
            Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 4),
          buttons,
        ],
      );
    },
  );
}
