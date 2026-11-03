import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

Future<FrozenPortion?> chooseFrozenForBrew(
  BuildContext context,
  List<FrozenPortion> portions,
  double grams,
) {
  final s = AppLocalizations.of(context)!;
  final enough =
      portions.where((p) => p.remainingGrams + 1e-6 >= grams).toList()
        ..sort((a, b) => a.frozenDate.compareTo(b.frozenDate));
  return showDialog<FrozenPortion>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('brew-choose-frozen'),
      title: Text(s.thawWhichPortion),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.brewChooseFrozen(formatGrams(grams, regionalLocale.toString())),
            ),
            if (enough.isEmpty) Text(s.brewFrozenTooSmall),
            for (final portion in enough)
              ListTile(
                key: ValueKey('brew-frozen-${portion.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(portion.label),
                subtitle: Text(
                  s.frozenPortionOption(
                    portion.label,
                    formatGrams(
                      portion.remainingGrams,
                      regionalLocale.toString(),
                    ),
                    switch (DateTime.tryParse(portion.frozenDate)) {
                      final date? => formatRegionalDate(date, regionalLocale),
                      null => portion.frozenDate,
                    },
                  ),
                ),
                onTap: () => Navigator.pop(context, portion),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
      ],
    ),
  );
}
