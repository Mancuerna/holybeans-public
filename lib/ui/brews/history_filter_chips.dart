import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/history_filters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Active filters with their values and individual clear actions.
class HistoryFilterChips extends StatelessWidget {
  const HistoryFilterChips({
    super.key,
    required this.filters,
    required this.coffees,
  });

  final HistoryFilters filters;
  final List<Coffee> coffees;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final coffee = coffees
        .where((coffee) => coffee.id == filters.coffeeId)
        .firstOrNull;
    final range = filters.dateRange;
    final rating = filters.minimumRating;
    void clear(VoidCallback change) => filters.update(change);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (filters.coffeeId != null)
                _ActiveFilter(
                  maxLabelWidth: (constraints.maxWidth - 88).clamp(48, 220),
                  id: 'coffee',
                  label: coffee?.name ?? s.historyFilters,
                  clearLabel: s.historyClearFilter,
                  onDeleted: () => clear(() => filters.coffeeId = null),
                ),
              if (filters.methodName case final method?)
                _ActiveFilter(
                  maxLabelWidth: (constraints.maxWidth - 88).clamp(48, 220),
                  id: 'method',
                  label: method,
                  clearLabel: s.historyClearFilter,
                  onDeleted: () => clear(() {
                    filters.methodId = null;
                    filters.methodName = null;
                  }),
                ),
              if (range != null)
                _ActiveFilter(
                  maxLabelWidth: (constraints.maxWidth - 88).clamp(48, 220),
                  id: 'date',
                  label: s.historyDateRangeValue(
                    formatRegionalDate(range.start, regionalLocale),
                    formatRegionalDate(range.end, regionalLocale),
                  ),
                  clearLabel: s.historyClearFilter,
                  onDeleted: () => clear(() => filters.dateRange = null),
                ),
              if (rating != null)
                _ActiveFilter(
                  maxLabelWidth: (constraints.maxWidth - 88).clamp(48, 220),
                  id: 'rating',
                  label:
                      '${formatDecimal(rating, pattern: '0.#', locale: regionalLocale.toString())}+ ★',
                  clearLabel: s.historyClearFilter,
                  onDeleted: () => clear(() => filters.minimumRating = null),
                ),
              TextButton(
                onPressed: () => filters.update(filters.clearAll),
                child: Text(s.clearFilters),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFilter extends StatelessWidget {
  const _ActiveFilter({
    required this.id,
    required this.maxLabelWidth,
    required this.label,
    required this.clearLabel,
    required this.onDeleted,
  });

  final String id;
  final double maxLabelWidth;
  final String label;
  final String clearLabel;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) => InputChip(
    key: ValueKey('history-active-$id'),
    label: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxLabelWidth),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    selected: true,
    showCheckmark: false,
    onDeleted: onDeleted,
    deleteButtonTooltipMessage: '$clearLabel: $label',
  );
}
