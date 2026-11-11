import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/coffee_selection_sheet.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Filters of the brew history. Owned by the shell, so other screens (e.g.
/// a method's brews in Equipment) can open the history already filtered.
class HistoryFilters extends ChangeNotifier {
  /// Archived brews are listed too. Set from its own button, outside the
  /// filters, so it neither counts as one nor is cleared with them.
  bool showArchived = false;
  String? coffeeId;
  String? methodId;
  String? methodName;
  DateTimeRange? dateRange;
  double? minimumRating;
  int navigationRevision = 0;

  void resetForNavigation() {
    clearAll();
    navigationRevision++;
  }

  int get activeCount => [
    coffeeId != null,
    methodName != null,
    dateRange != null,
    minimumRating != null,
  ].where((active) => active).length;

  /// Applies [change] to the fields and notifies listeners.
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  void clearAll() {
    coffeeId = null;
    methodId = null;
    methodName = null;
    dateRange = null;
    minimumRating = null;
  }
}

/// Opens every filter of the history in a sheet that follows [filters] as
/// they change.
Future<void> showHistoryFilters(
  BuildContext context,
  HistoryFilters filters, {
  required List<Coffee> coffees,
  required List<String> methods,
}) async {
  final s = AppLocalizations.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    // The filters notify on every change, so the sheet follows them.
    builder: (sheetContext) => ListenableBuilder(
      listenable: filters,
      builder: (sheetContext, _) {
        final activeFilterCount = filters.activeCount;
        final today = DateUtils.dateOnly(DateTime.now());
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
          ),
          child: SingleChildScrollView(
            key: const ValueKey('history-filter-sheet'),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.historyFilters,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  s.historyFilterHint,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _CoffeeFilterField(
                  coffees: coffees,
                  value: filters.coffeeId,
                  onChanged: (id) =>
                      filters.update(() => filters.coffeeId = id),
                ),
                const SizedBox(height: 12),
                _dropdown<String>(
                  key: const ValueKey('history-method-filter'),
                  label: s.method,
                  value: filters.methodName ?? '',
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.anyMethod)),
                    ...methods.map(
                      (methodName) => DropdownMenuItem(
                        value: methodName,
                        child: Text(
                          methodName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => filters.update(() {
                    filters.methodId = null;
                    filters.methodName = value == null || value.isEmpty
                        ? null
                        : value;
                  }),
                ),
                const SizedBox(height: 4),
                ListTile(
                  key: const ValueKey('history-date-filter'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.dateRange),
                  subtitle: Text(
                    filters.dateRange == null
                        ? s.anyDate
                        : s.historyDateRangeValue(
                            formatRegionalDate(
                              filters.dateRange!.start,
                              regionalLocale,
                            ),
                            formatRegionalDate(
                              filters.dateRange!.end,
                              regionalLocale,
                            ),
                          ),
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () => _chooseDateRange(sheetContext, filters),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (key, label, start) in [
                      ('today', s.today, today),
                      (
                        'week',
                        s.historyLastSevenDays,
                        DateTime(today.year, today.month, today.day - 6),
                      ),
                      (
                        'month',
                        s.historyThisMonth,
                        DateTime(today.year, today.month),
                      ),
                    ])
                      ActionChip(
                        key: ValueKey('history-period-$key'),
                        label: Text(label),
                        onPressed: () => filters.update(
                          () => filters.dateRange = DateTimeRange(
                            start: start,
                            end: today,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _dropdown<double>(
                  key: const ValueKey('history-rating-filter'),
                  label: s.minimumRating,
                  value: filters.minimumRating ?? -1,
                  items: [
                    DropdownMenuItem(value: -1, child: Text(s.anyRating)),
                    for (var halfStep = 0; halfStep <= 20; halfStep++)
                      DropdownMenuItem(
                        value: halfStep / 2,
                        child: Text(
                          '${formatDecimal(halfStep / 2, pattern: '0.#', locale: regionalLocale.toString())}+',
                        ),
                      ),
                  ],
                  onChanged: (value) => filters.update(
                    () => filters.minimumRating = value == null || value < 0
                        ? null
                        : value,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.historyRatingFilterBehavior,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ),
                ),
                if (activeFilterCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => filters.update(filters.clearAll),
                      child: Text(s.clearFilters),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Asks for the first and last day, in the device's regional format.
Future<void> _chooseDateRange(
  BuildContext context,
  HistoryFilters filters,
) async {
  final strings = AppLocalizations.of(context);
  final deviceLocale = regionalLocale;
  final today = DateUtils.dateOnly(DateTime.now());
  final selectedStart = await showDatePicker(
    context: context,
    locale: deviceLocale,
    helpText: strings.selectStartDate,
    initialDate: filters.dateRange?.start ?? today,
    firstDate: DateTime(1900),
    lastDate: DateTime(2100, 12, 31),
  );
  if (selectedStart == null || !context.mounted) return;

  final start = DateUtils.dateOnly(selectedStart);
  final currentEnd = filters.dateRange?.end;
  final selectedEnd = await showDatePicker(
    context: context,
    locale: deviceLocale,
    helpText: strings.selectEndDate,
    initialDate: currentEnd == null || currentEnd.isBefore(start)
        ? start
        : currentEnd,
    firstDate: start,
    lastDate: DateTime(2100, 12, 31),
  );
  if (selectedEnd != null && context.mounted) {
    filters.update(
      () => filters.dateRange = DateTimeRange(
        start: start,
        end: DateUtils.dateOnly(selectedEnd),
      ),
    );
  }
}

/// The coffee filter, labelled like the form fields; it opens a searchable
/// list, since a journal can hold hundreds of coffees.
class _CoffeeFilterField extends StatelessWidget {
  const _CoffeeFilterField({
    required this.coffees,
    required this.value,
    required this.onChanged,
  });

  final List<Coffee> coffees;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final chosen = coffees.where((coffee) => coffee.id == value).firstOrNull;
    return InkWell(
      key: const ValueKey('history-bean-filter'),
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (_) => CoffeeSelectionSheet(
            coffees: coffees,
            allowAny: true,
            selected: value,
          ),
        );
        // '' is "Any bean"; null is a dismissed sheet.
        if (picked != null) onChanged(picked.isEmpty ? null : picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: s.coffeeBlock,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          chosen?.name ?? s.anyBean,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// One filter chosen from a list, labelled like the form fields.
Widget _dropdown<T>({
  required Key key,
  required String label,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) => InputDecorator(
  decoration: InputDecoration(labelText: label),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      key: key,
      value: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
    ),
  ),
);
