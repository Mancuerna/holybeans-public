import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class ComparisonValuesRow extends StatelessWidget {
  const ComparisonValuesRow({
    super.key,
    required this.label,
    this.a,
    this.b,
    this.difference,
    this.header = false,
    this.missing,
  });
  final String label;
  final String? a;
  final String? b;
  final String? difference;
  final bool header;

  /// What an empty value reads; "Not recorded" by default. A dash when a
  /// note above already says the whole column is empty.
  final String? missing;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = header
        ? theme.textTheme.titleSmall
        : theme.textTheme.bodyMedium;
    String present(String? value) => value == null || value.trim().isEmpty
        ? missing ?? s.comparisonMissing
        : value;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label, style: style)),
                const SizedBox(width: 10),
                Expanded(child: Text(present(a), style: style)),
                const SizedBox(width: 10),
                Expanded(child: Text(present(b), style: style)),
              ],
            ),
            if (difference != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(difference!, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
