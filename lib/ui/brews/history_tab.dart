import 'package:flutter/material.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/history_filter_chips.dart';
import 'package:holybeans/ui/brews/history_filters.dart';
import 'package:holybeans/ui/core/journal_search_toolbar.dart';
import 'package:holybeans/ui/core/page_layout.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:intl/intl.dart';

/// Brew history grouped by day, with search and filters.
class HistoryTab extends StatefulWidget {
  const HistoryTab({
    super.key,
    required this.data,
    required this.actions,
    required this.filters,
    this.options = const ListOptions(),
    this.onOptionsChanged,
  });

  final JournalData data;
  final JournalActions actions;
  final HistoryFilters filters;

  /// Order and archived brews, kept by the shell between launches.
  final ListOptions options;
  final ValueChanged<ListOptions>? onOptionsChanged;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final search = TextEditingController();
  late int navigationRevision = filters.navigationRevision;

  HistoryFilters get filters => widget.filters;
  ListOptions get options => widget.options;
  bool get ascending => options.brewsAscending;

  void _change(ListOptions changed) => widget.onOptionsChanged?.call(changed);

  /// Lists or hides archived brews, and remembers the choice.
  void _toggleArchived() {
    final show = !filters.showArchived;
    filters.update(() => filters.showArchived = show);
    _change(options.copyWith(showArchivedBrews: show));
  }

  @override
  void initState() {
    super.initState();
    search.addListener(_refresh);
    filters.addListener(_refresh);
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      oldWidget.filters.removeListener(_refresh);
      widget.filters.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    filters.removeListener(_refresh);
    search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (navigationRevision != filters.navigationRevision) {
      navigationRevision = filters.navigationRevision;
      search.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final coffees = widget.data.coffees;
    final brews = widget.data.brews;
    final s = AppLocalizations.of(context)!;
    final query = foldSuggestion(search.text);
    final coffeeById = {for (final coffee in coffees) coffee.id: coffee};
    final coffeeOptions = coffees.toList()
      ..sort(
        (first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );
    final methodsInHistory =
        {...brews.map((brew) => brew.methodName), ?filters.methodName}.toList()
          ..sort(
            (first, second) =>
                first.toLowerCase().compareTo(second.toLowerCase()),
          );
    final activeFilterCount = filters.activeCount;
    final visible =
        brews.where((brew) {
          if (!filters.showArchived && brew.archivedAtMs != null) return false;
          if (query.isNotEmpty &&
              !foldSuggestion(
                '${coffeeById[brew.coffeeId]?.name ?? ''} ${coffeeById[brew.coffeeId]?.roaster ?? ''} ${brew.methodName} ${brew.grinderName ?? ''} ${brew.notes ?? ''}',
              ).contains(query)) {
            return false;
          }
          if (filters.coffeeId != null && brew.coffeeId != filters.coffeeId) {
            return false;
          }
          if (filters.methodId case final methodId?) {
            if (brew.methodId != null) {
              if (brew.methodId != methodId) return false;
            } else if (filters.methodName != brew.methodName) {
              return false;
            }
          } else if (filters.methodName != null &&
              brew.methodName != filters.methodName) {
            return false;
          }
          final dateRange = filters.dateRange;
          if (dateRange != null) {
            final brewedAt = DateTime.fromMillisecondsSinceEpoch(
              brew.brewedAtMs,
            );
            final start = DateTime(
              dateRange.start.year,
              dateRange.start.month,
              dateRange.start.day,
            );
            final endExclusive = nextLocalDayStart(dateRange.end);
            if (brewedAt.isBefore(start) || !brewedAt.isBefore(endExclusive)) {
              return false;
            }
          }
          final minimumRating = filters.minimumRating;
          if (minimumRating != null &&
              (brew.rating == null || brew.rating! < minimumRating)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final byTime = a.brewedAtMs.compareTo(b.brewedAtMs);
          if (byTime != 0) return ascending ? byTime : -byTime;
          final byCreated = b.createdAtMs.compareTo(a.createdAtMs);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    return JournalListPage(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          JournalSearchToolbar(
            controller: search,
            actions: [
              IconButton(
                key: const ValueKey('history-filter-button'),
                tooltip: activeFilterCount == 0
                    ? s.historyFilters
                    : s.historyActiveFilters(activeFilterCount),
                onPressed: () => showHistoryFilters(
                  context,
                  filters,
                  coffees: coffeeOptions,
                  methods: methodsInHistory,
                ),
                icon: Badge(
                  isLabelVisible: activeFilterCount > 0,
                  label: Text('$activeFilterCount'),
                  child: const Icon(Icons.filter_list_rounded),
                ),
              ),
              IconButton(
                key: const ValueKey('history-show-archived'),
                tooltip: filters.showArchived
                    ? s.hideArchivedBrews
                    : s.showArchivedBrews,
                isSelected: filters.showArchived,
                style: IconButton.styleFrom(
                  backgroundColor: filters.showArchived
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: filters.showArchived
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                onPressed: _toggleArchived,
                icon: const Icon(Icons.archive_outlined),
                selectedIcon: const Icon(Icons.archive_rounded),
              ),
              PopupMenuButton<bool>(
                key: const ValueKey('history-sort'),
                tooltip:
                    '${s.sortBrews}: ${ascending ? s.sortAscending : s.sortDescending}',
                icon: const Icon(Icons.sort_rounded),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: true,
                    checked: ascending,
                    child: Text(s.sortAscending),
                  ),
                  CheckedPopupMenuItem(
                    value: false,
                    checked: !ascending,
                    child: Text(s.sortDescending),
                  ),
                ],
                onSelected: (value) =>
                    _change(options.copyWith(brewsAscending: value)),
              ),
            ],
          ),
          if (activeFilterCount > 0) ...[
            const SizedBox(height: 8),
            HistoryFilterChips(filters: filters, coffees: coffees),
          ],
          const SizedBox(height: 12),
          if (visible.isEmpty)
            EmptyMessage(
              query.isEmpty && activeFilterCount == 0
                  ? s.noBrews
                  : s.noMatchingBrews,
            ),
        ],
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final brew = visible[index];
        final card = BrewCard(
          brew: brew,
          data: widget.data,
          actions: widget.actions,
          showDate: false,
        );
        if (index > 0 &&
            _sameLocalDay(visible[index - 1].brewedAtMs, brew.brewedAtMs)) {
          return card;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_dayHeader(context, brew.brewedAtMs), card],
        );
      },
    );
  }

  static bool _sameLocalDay(int firstMs, int secondMs) {
    final first = DateTime.fromMillisecondsSinceEpoch(firstMs);
    final second = DateTime.fromMillisecondsSinceEpoch(secondMs);
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  Widget _dayHeader(BuildContext context, int brewedAtMs) {
    final s = AppLocalizations.of(context)!;
    final day = DateTime.fromMillisecondsSinceEpoch(brewedAtMs);
    final now = DateTime.now();
    final label = _sameLocalDay(brewedAtMs, now.millisecondsSinceEpoch)
        ? s.today
        : _sameLocalDay(
            brewedAtMs,
            DateTime(now.year, now.month, now.day - 1).millisecondsSinceEpoch,
          )
        ? s.yesterday
        : (day.year == now.year
                  ? DateFormat.MMMMEEEEd(regionalLocale.toString())
                  : DateFormat.yMMMMEEEEd(regionalLocale.toString()))
              .format(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
