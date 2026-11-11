import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/bean_roaster_groups.dart';
import 'package:holybeans/domain/freshness_order.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/bean_list_data.dart';
import 'package:holybeans/ui/beans/roaster_group_header.dart';
import 'package:holybeans/ui/core/journal_search_toolbar.dart';
import 'package:holybeans/ui/core/page_layout.dart';
import 'package:holybeans/ui/core/swipe_actions.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Beans: Available, Frozen and Archived tabs with search, sort, favourites
/// first and card density.
class BeansTab extends StatefulWidget {
  const BeansTab({
    super.key,
    required this.data,
    required this.actions,
    required this.tabs,
    required this.onOpenCalendar,
    this.options = const ListOptions(),
    this.onOptionsChanged,
  });

  final JournalData data;
  final VoidCallback onOpenCalendar;
  final JournalActions actions;

  /// Sort and density, kept by the shell between launches.
  final ListOptions options;
  final ValueChanged<ListOptions>? onOptionsChanged;

  /// Owned by the shell so other tabs can open a given bean tab.
  final TabController tabs;

  @override
  State<BeansTab> createState() => _BeansTabState();
}

class _BeansTabState extends State<BeansTab> {
  final search = TextEditingController();
  final _expandedRoasters = <(int, String)>{};
  (JournalData, List<FrozenPortion>)? _listKey;
  late BeanListData _aggregates;

  ListOptions get options => widget.options;
  bool get archivedTab => widget.tabs.index == 2;
  bool get frozenTab => widget.tabs.index == 1;
  int get sortMode =>
      (archivedTab
              ? options.archivedBeanSort
              : frozenTab
              ? options.frozenBeanSort
              : options.beanSort)
          .index;
  bool get favoritesFirst => options.favoritesFirst;
  bool get ascending => archivedTab
      ? options.archivedBeansAscending
      : frozenTab
      ? options.frozenBeansAscending
      : options.beansAscending;
  bool get compact =>
      archivedTab ? options.archivedBeansCompact : options.beansCompact;

  void _change(ListOptions changed) => widget.onOptionsChanged?.call(changed);

  JournalActions get actions => widget.actions;

  @override
  void initState() {
    super.initState();
    search.addListener(_refresh);
    widget.tabs.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(BeansTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs != widget.tabs) {
      oldWidget.tabs.removeListener(_onTabChanged);
      widget.tabs.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_onTabChanged);
    search.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _onTabChanged() {
    if (!widget.tabs.indexIsChanging) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.data, actions.read.portions);
    if (key != _listKey) {
      _listKey = key;
      _aggregates = BeanListData(key.$1, key.$2);
    }
    final s = AppLocalizations.of(context)!;
    final query = foldSuggestion(search.text);
    final mostRecentBrewByCoffee = _aggregates.lastBrewAt;
    final latestRoastDateByCoffee = _aggregates.latestRoastDates;
    final oldestFrozenDates = _aggregates.oldestFrozenDates;
    final counts = _aggregates.tabs.map((coffees) => coffees.length).toList();
    final visible = _aggregates.tabs[widget.tabs.index].where((coffee) {
      return query.isEmpty ||
          _aggregates.searchText[coffee.id]!.contains(query);
    }).toList();
    int compareName(Coffee first, Coffee second) {
      final byName = first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      );
      return byName != 0
          ? (ascending ? byName : -byName)
          : first.id.compareTo(second.id);
    }

    visible.sort((first, second) {
      if (favoritesFirst && first.isFavorite != second.isFavorite) {
        return first.isFavorite ? -1 : 1;
      }
      switch (sortMode) {
        case 1:
          final firstBrew = mostRecentBrewByCoffee[first.id];
          final secondBrew = mostRecentBrewByCoffee[second.id];
          if (firstBrew == null) {
            return secondBrew == null ? compareName(first, second) : 1;
          }
          if (secondBrew == null) return -1;
          final byBrew = ascending
              ? firstBrew.compareTo(secondBrew)
              : secondBrew.compareTo(firstBrew);
          return byBrew != 0 ? byBrew : compareName(first, second);
        case 2:
          final firstRoast = latestRoastDateByCoffee[first.id];
          final secondRoast = latestRoastDateByCoffee[second.id];
          if (firstRoast == null) {
            return secondRoast == null ? compareName(first, second) : 1;
          }
          if (secondRoast == null) return -1;
          final byRoastDate = ascending
              ? firstRoast.compareTo(secondRoast)
              : secondRoast.compareTo(firstRoast);
          return byRoastDate != 0 ? byRoastDate : compareName(first, second);
        case 4:
          final firstDate = oldestFrozenDates[first.id];
          final secondDate = oldestFrozenDates[second.id];
          if (firstDate == null) {
            return secondDate == null ? compareName(first, second) : 1;
          }
          if (secondDate == null) return -1;
          final byDate = firstDate.compareTo(secondDate);
          return byDate != 0
              ? (ascending ? byDate : -byDate)
              : compareName(first, second);
        case 3:
          final byFreshness = compareFreshness(
            actions.read.freshnessToday(first),
            actions.read.freshnessToday(second),
            ascending: ascending,
          );
          return byFreshness != 0 ? byFreshness : compareName(first, second);
        default:
          return compareName(first, second);
      }
    });
    return Column(
      children: [
        TabBar(
          key: const ValueKey('bean-tabs'),
          controller: widget.tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final (index, label) in [
              s.beansAvailable,
              s.beansFrozen,
              s.beansArchived,
            ].indexed)
              Tab(child: Text('$label (${counts[index]})', maxLines: 1)),
          ],
        ),
        Expanded(child: _beanList(context, visible, query)),
      ],
    );
  }

  Widget _beanList(BuildContext context, List<Coffee> visible, String query) {
    final rows = <Object>[];
    if (options.beansByRoaster) {
      final fresh = _aggregates.freshGrams;
      final frozen = _aggregates.frozenGrams;
      final byId = {for (final coffee in visible) coffee.id: coffee};
      final groups = groupBeansByRoaster([
        for (final coffee in visible)
          (
            id: coffee.id,
            roaster: coffee.roaster,
            grams: frozenTab ? frozen[coffee.id] : fresh[coffee.id],
            phase: archivedTab || frozenTab || (fresh[coffee.id] ?? 1) <= 0
                ? null
                : actions.read.freshnessToday(coffee)?.phase,
          ),
      ]);
      for (final group in groups) {
        rows.add(group);
        if (query.isNotEmpty ||
            _expandedRoasters.contains((widget.tabs.index, group.key))) {
          rows.addAll(group.beans.map((bean) => byId[bean.id]!));
        }
      }
    } else {
      rows.addAll(visible);
    }
    return JournalListPage(
      header: _listHeader(context, visible.isEmpty, query),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is BeanRoasterGroup) {
          final key = (widget.tabs.index, row.key);
          return RoasterGroupHeader(
            group: row,
            showStock: !archivedTab,
            expanded: query.isNotEmpty || _expandedRoasters.contains(key),
            onTap: query.isNotEmpty
                ? null
                : () => setState(() {
                    if (!_expandedRoasters.remove(key)) {
                      _expandedRoasters.add(key);
                    }
                  }),
          );
        }
        return _coffeeCard(row as Coffee);
      },
    );
  }

  Widget _listHeader(BuildContext context, bool empty, String query) {
    final s = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        JournalSearchToolbar(
          controller: search,
          actions: [
            _viewMenu(context),
            IconButton(
              key: const ValueKey('beans-calendar'),
              tooltip: s.freshnessCalendar,
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                widget.onOpenCalendar();
              },
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            _sortMenu(context),
          ],
        ),
        const SizedBox(height: 12),
        if (empty) EmptyMessage(query.isEmpty ? s.noBeans : s.noMatchingBeans),
      ],
    );
  }

  Widget _viewMenu(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopupMenuButton<int>(
      key: const ValueKey('beans-view-menu'),
      tooltip:
          '${s.listView}: ${options.beansByRoaster ? s.beansViewRoasters : s.beansViewCoffees}',
      icon: Icon(
        options.beansByRoaster
            ? Icons.workspaces_outline
            : Icons.view_agenda_outlined,
      ),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          key: const ValueKey('beans-view-coffees'),
          value: 0,
          checked: !options.beansByRoaster,
          child: Text(s.beansViewCoffees),
        ),
        CheckedPopupMenuItem(
          key: const ValueKey('beans-view-roasters'),
          value: 1,
          checked: options.beansByRoaster,
          child: Text(s.beansViewRoasters),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          key: const ValueKey('bean-density-toggle'),
          value: 2,
          checked: compact,
          child: Text(s.compactCards),
        ),
      ],
      onSelected: (value) => _change(
        value == 2
            ? archivedTab
                  ? options.copyWith(archivedBeansCompact: !compact)
                  : options.copyWith(beansCompact: !compact)
            : options.copyWith(beansByRoaster: value == 1),
      ),
    );
  }

  Widget _sortMenu(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopupMenuButton<int>(
      key: const ValueKey('bean-sort'),
      tooltip:
          '${s.sortBeans}: ${_beanSortLabel(s, sortMode)}, ${ascending ? s.sortAscending : s.sortDescending}',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.sort_rounded),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 0,
          checked: sortMode == 0,
          child: Text(s.sortBeansByName),
        ),
        CheckedPopupMenuItem(
          value: 1,
          checked: sortMode == 1,
          child: Text(s.sortBeansByRecentBrew),
        ),
        CheckedPopupMenuItem(
          value: 2,
          checked: sortMode == 2,
          child: Text(s.sortBeansByRoastDate),
        ),
        if (frozenTab)
          CheckedPopupMenuItem(
            value: 4,
            checked: sortMode == 4,
            child: Text(s.sortBeansByFrozenDate),
          )
        else
          CheckedPopupMenuItem(
            value: 3,
            checked: sortMode == 3,
            child: Text(s.sortBeansByFreshness),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: -2,
          checked: ascending,
          child: Text(s.sortAscending),
        ),
        CheckedPopupMenuItem(
          value: -3,
          checked: !ascending,
          child: Text(s.sortDescending),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          key: const ValueKey('bean-favorites-first'),
          value: _favoritesFirstOption,
          checked: favoritesFirst,
          child: Text(s.favoritesFirst),
        ),
      ],
      onSelected: _changeSort,
    );
  }

  void _changeSort(int value) => _change(switch (value) {
    _favoritesFirstOption => options.copyWith(favoritesFirst: !favoritesFirst),
    -2 || -3 =>
      archivedTab
          ? options.copyWith(archivedBeansAscending: value == -2)
          : frozenTab
          ? options.copyWith(frozenBeansAscending: value == -2)
          : options.copyWith(beansAscending: value == -2),
    // A new criterion starts in its natural order: names A–Z,
    // dates newest first, freshness most urgent first.
    // Frozen dates start oldest first; each tab keeps its order.
    _ when sortMode != value =>
      archivedTab
          ? options.copyWith(
              archivedBeanSort: BeanSort.values[value],
              archivedBeansAscending: value == 0,
            )
          : frozenTab
          ? options.copyWith(
              frozenBeanSort: BeanSort.values[value],
              frozenBeansAscending: value == 0 || value == 4,
            )
          : options.copyWith(
              beanSort: BeanSort.values[value],
              beansAscending: value == 0,
            ),
    _ => options,
  });

  Widget _coffeeCard(Coffee coffee) {
    final s = AppLocalizations.of(context)!;
    return SwipeActions(
      id: coffee.id,
      // Right brews with an available bean; left archives it, or
      // brings an archived one back.
      start: coffee.archivedAtMs == null && widget.tabs.index == 0
          ? SwipeAction(
              icon: Icons.coffee_maker_outlined,
              label: s.actionBrew,
              primary: true,
              run: () => actions.navigation.openBrewForm(
                widget.data.coffees,
                initialCoffeeId: coffee.id,
              ),
            )
          : null,
      end: SwipeAction(
        icon: coffee.archivedAtMs == null
            ? Icons.archive_outlined
            : Icons.unarchive_outlined,
        label: coffee.archivedAtMs == null ? s.archiveBean : s.unarchiveBean,
        run: () => _toggleArchived(coffee),
      ),
      child: BeanCard(
        coffee: coffee,
        data: widget.data,
        actions: actions,
        compact: compact,
      ),
    );
  }

  Future<void> _toggleArchived(Coffee coffee) async {
    if (coffee.archivedAtMs == null) {
      await actions.commands.confirmCoffeeArchive(coffee);
      return;
    }
    try {
      await actions.commands.mutations.setCoffeeArchived(
        coffee.id,
        archived: false,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    }
  }

  static const _favoritesFirstOption = -1;

  String _beanSortLabel(AppLocalizations s, int mode) => switch (mode) {
    1 => s.sortBeansByRecentBrew,
    2 => s.sortBeansByRoastDate,
    3 => s.sortBeansByFreshness,
    4 => s.sortBeansByFrozenDate,
    _ => s.sortBeansByName,
  };
}
