import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/history_filter_chips.dart';
import 'package:holybeans/ui/brews/history_filters.dart';
import 'package:holybeans/ui/brews/history_view_model.dart';
import 'package:holybeans/ui/brews/paged_history_view_model.dart';
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
  late final HistoryViewModel model = widget.data.reads == null
      ? HistoryViewModel()
      : PagedHistoryViewModel(widget.data.reads!);
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
    _updateSearch();
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      oldWidget.filters.removeListener(_refresh);
      widget.filters.addListener(_refresh);
    }
    _updateSearch();
  }

  @override
  void dispose() {
    filters.removeListener(_refresh);
    search.dispose();
    model.dispose();
    super.dispose();
  }

  void _refresh() {
    if (navigationRevision != filters.navigationRevision) {
      navigationRevision = filters.navigationRevision;
      search.clear();
    }
    _updateSearch();
    setState(() {});
  }

  HistoryQuery get _query {
    final range = filters.dateRange;
    return (
      text: foldSuggestion(search.text),
      archived: filters.showArchived,
      ascending: ascending,
      coffeeId: filters.coffeeId,
      methodId: filters.methodId,
      methodName: filters.methodName,
      startMs: range == null
          ? null
          : DateTime(
              range.start.year,
              range.start.month,
              range.start.day,
            ).millisecondsSinceEpoch,
      endMs: range == null
          ? null
          : nextLocalDayStart(range.end).millisecondsSinceEpoch,
      minimumRating: filters.minimumRating,
    );
  }

  void _updateSearch() => model.update(widget.data, _query);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => _buildList(context),
  );

  Widget _buildList(BuildContext context) {
    final coffees = widget.data.coffees;
    final s = AppLocalizations.of(context);
    final query = _query.text;
    final activeFilterCount = filters.activeCount;
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
                  coffees: model.coffeeOptions,
                  methods: {...model.methods, ?filters.methodName}.toList()
                    ..sort(
                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                    ),
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
          if (model.error != null && model is PagedHistoryViewModel)
            TextButton(
              onPressed: (model as PagedHistoryViewModel).retry,
              child: Text(s.dataError),
            ),
          if (model.busy)
            const LinearProgressIndicator(
              key: ValueKey('history-search-progress'),
            ),
          if (!model.busy && model.length == 0)
            EmptyMessage(
              model.error != null
                  ? s.dataError
                  : query.isEmpty && activeFilterCount == 0
                  ? s.noBrews
                  : s.noMatchingBrews,
            ),
        ],
      ),
      itemCount: model.length,
      itemBuilder: (context, index) {
        final brew = model.brewAt(index);
        if (brew == null) {
          return SizedBox(
            height: 120,
            child: Center(
              child: model.error != null && model is PagedHistoryViewModel
                  ? TextButton(
                      onPressed: (model as PagedHistoryViewModel).retry,
                      child: Text(s.dataError),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final card = BrewCard(
          brew: brew,
          data: widget.data,
          actions: widget.actions,
          showDate: false,
        );
        final previous = model.brewAt(index - 1);
        if (previous != null &&
            _sameLocalDay(previous.brewedAtMs, brew.brewedAtMs)) {
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
    final s = AppLocalizations.of(context);
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
