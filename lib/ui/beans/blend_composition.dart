import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

class BlendComposition extends StatefulWidget {
  const BlendComposition({
    super.key,
    required this.coffee,
    required this.actions,
    required this.data,
  });
  final Coffee coffee;
  final JournalActions actions;
  final JournalData data;
  @override
  State<BlendComposition> createState() => _BlendCompositionState();
}

class _BlendCompositionState extends State<BlendComposition> {
  late final rows = widget.actions.read.queries.blendContributions(
    widget.coffee.id,
  );
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final date = formatRegionalDate(
      DateTime.fromMillisecondsSinceEpoch(widget.coffee.mixedAtMs!),
      regionalLocale,
    );
    return FutureBuilder<List<StockAdjustment>>(
      future: rows,
      builder: (_, snapshot) {
        final parts = snapshot.data ?? const <StockAdjustment>[];
        final locale = regionalLocale.toString();
        double weight(StockAdjustment r) => r.previousGrams! - r.resultingGrams;
        final total = parts.fold<double>(0, (sum, r) => sum + weight(r));
        final dates =
            parts.map((r) => r.sourceRoastDate).nonNulls.toSet().toList()
              ..sort();
        String regional(String value) =>
            formatRegionalDate(DateTime.parse(value), regionalLocale);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailRow(s.blendMixedOn, date),
            if (dates.isNotEmpty)
              DetailRow(
                s.roastDate,
                dates.length == 1
                    ? regional(dates.first)
                    : '${regional(dates.first)} – ${regional(dates.last)}',
              ),
            for (final row in parts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.data.coffees
                      .firstWhere((c) => c.id == row.coffeeId)
                      .name,
                ),
                subtitle: Text(
                  [
                    formatGrams(weight(row), locale),
                    '${formatDecimal(weight(row) * 100 / total, pattern: '0.#', locale: locale)} %',
                    row.sourceRoastDate == null
                        ? s.blendUnknownRoast
                        : regional(row.sourceRoastDate!),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.actions.navigation.showCoffeeDetailsById(
                  row.coffeeId,
                ),
              ),
          ],
        );
      },
    );
  }
}
