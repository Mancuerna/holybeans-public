import 'package:flutter/material.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/formatters.dart';

class FreshnessHelp extends StatelessWidget {
  const FreshnessHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(s.freshnessHelpTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.freshnessHelp),
          const SizedBox(height: 24),
          Text(
            s.freshnessGuideTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(s.freshnessGuideNote),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final label in [
                  s.roastLevel,
                  s.method,
                  s.phaseDegassing,
                  s.phasePrime,
                  s.phaseGood,
                  s.phaseAging,
                  s.phaseStale,
                ])
                  DataColumn(label: Text(label)),
              ],
              rows: [
                for (final roast in degassingCurves.keys)
                  for (final style in BrewStyle.values) _row(s, roast, style),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  DataRow _row(AppLocalizations s, String roast, BrewStyle style) {
    final window = freshnessWindow(roastLevel: roast, style: style);
    return DataRow(
      cells: [
        for (final value in [
          roastLevelLabel(s, roast),
          style == BrewStyle.espresso ? s.styleEspresso : s.styleFilter,
          '0–${window.primeStart - 1}',
          '${window.primeStart}–${window.primeEnd}',
          '${window.primeEnd + 1}–${window.goodUntil}',
          '${window.goodUntil + 1}–${window.agingUntil}',
          s.freshnessGuideFrom(window.agingUntil + 1),
        ])
          DataCell(Text(value)),
      ],
    );
  }
}
