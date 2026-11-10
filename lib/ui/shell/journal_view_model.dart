import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/brew_overview.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

/// The journal as the shell shows it: the live rows, the settings every tab
/// follows and whether they have arrived.
///
/// Subscribes to the repository once, when created, and notifies on every
/// change, so the shell rebuilds from one listenable and its tabs receive an
/// immutable [JournalData].
class JournalViewModel extends ChangeNotifier {
  JournalViewModel({
    required this.repository,
    required BrewParameterSettings parameterSettings,
    required this.listOptionsSettings,
  }) {
    _subscriptions.addAll([
      _watch(_coffees, repository.watchCoffees(includeArchived: true)),
      _watch(_overview, repository.reads.watchOverview()),
      _watch(_lots, repository.watchLots()),
      _watch(_adjustments, repository.watchStockAdjustments()),
      _watch(_components, repository.watchComponents()),
      _watch(_methods, repository.watchMethods(includeArchived: true)),
      _watch(_portions, repository.watchFrozenPortions()),
      _watch(_covers, repository.watchCoffeeCovers()),
      _watch(_hidden, parameterSettings.watchHidden()),
    ]);
  }

  final JournalRepository repository;

  /// Where the list options are kept between launches.
  final ListOptionsSettings listOptionsSettings;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _disposed = false;

  final _coffees = _Live<List<Coffee>>(const []);
  final _overview = _Live<BrewOverview>(const BrewOverview());
  final _adjustments = _Live<List<StockAdjustment>>(const []);
  final _lots = _Live<List<CoffeeLot>>(const []);
  final _components = _Live<List<CoffeeComponent>>(const []);
  final _methods = _Live<List<BrewMethod>>(const []);
  final _portions = _Live<List<FrozenPortion>>(const []);
  final _covers = _Live<Map<String, String>>(const {});
  final _hidden = _Live<Set<BrewParameter>>(const {});
  var _listOptions = const ListOptions();
  int _listOptionsRequest = 0;

  /// Phases worked out since the journal last changed, for [_phasesDay].
  final _phases = <(String, BrewStyle?), FreshnessToday?>{};
  DateTime? _phasesDay;

  JournalData? _data;
  Map<String, BrewStyle>? _lastStyles;

  /// Coffees, brews, lots, origins and covers as they are now, archived
  /// ones included. Reused until one of these collections changes.
  JournalData get data => _data ??= JournalData(
    reads: repository.reads,
    overview: _overview.value,
    coffees: _coffees.value,
    brews: _overview.value.previews,
    lots: _lots.value,
    adjustments: _adjustments.value,
    components: _components.value,
    covers: _covers.value,
  );

  List<Coffee> get coffees => _coffees.value;
  List<CoffeeLot> get lots => _lots.value;
  List<BrewMethod> get methods => _methods.value;
  List<FrozenPortion> get portions => _portions.value;

  /// Parameters hidden in Settings.
  Set<BrewParameter> get hiddenParameters => _hidden.value;

  /// Sort orders and archived toggles of the lists, as last chosen.
  ListOptions get listOptions => _listOptions;

  /// Whether a list the tabs need has not arrived yet.
  ///
  /// Covers and hidden parameters do not count: the tabs work without them.
  bool get loading => [
    _coffees,
    _overview,
    _lots,
    _adjustments,
    _components,
    _methods,
    _portions,
  ].any((live) => !live.loaded);

  /// Whether the journal could not be read. A failed freezer list only
  /// leaves the freezer empty.
  bool get hasError => [
    _coffees,
    _overview,
    _lots,
    _adjustments,
    _components,
    _methods,
  ].any((live) => live.error != null);

  /// Whether no coffee is left to brew with.
  bool get everyCoffeeArchived =>
      _coffees.value.every((coffee) => coffee.archivedAtMs != null);

  /// The newest active brew of a coffee still active: what the Brew button
  /// starts from.
  Brew? get latestUsableBrew {
    final active = {
      for (final coffee in _coffees.value)
        if (coffee.archivedAtMs == null) coffee.id,
    };
    return _overview.value.latestActive
        .where(
          (brew) => brew.archivedAtMs == null && active.contains(brew.coffeeId),
        )
        .firstOrNull;
  }

  /// The phase [coffee] is in today for [style], or for the style last
  /// brewed with it (see [freshnessToday]). Home and the bean cards ask for
  /// the same coffees on every rebuild; this works each one out once until
  /// the journal changes or the day turns.
  FreshnessToday? freshnessOf(Coffee coffee, {BrewStyle? style}) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    if (_phasesDay != day) {
      _phases.clear();
      _phasesDay = day;
    }
    return _phases.putIfAbsent(
      (coffee.id, style),
      () => freshnessToday(
        coffee,
        data: data,
        methods: methods,
        portions: portions,
        style: style ?? _lastStyleOf(coffee.id),
        now: now,
      ),
    );
  }

  BrewStyle _lastStyleOf(String coffeeId) {
    if (_lastStyles == null) {
      final latest = <String, Brew>{};
      for (final brew in _overview.value.previews) {
        final previous = latest[brew.coffeeId];
        if (previous == null || brew.brewedAtMs > previous.brewedAtMs) {
          latest[brew.coffeeId] = brew;
        }
      }
      _lastStyles = {
        for (final entry in latest.entries)
          entry.key: brewStyleOf(entry.value, methods),
      };
    }
    return _lastStyles![coffeeId] ?? BrewStyle.filter;
  }

  /// Loads saved list options without replacing newer user choices.
  Future<ListOptions> loadListOptions() async {
    final request = ++_listOptionsRequest;
    try {
      final options = await listOptionsSettings.load();
      if (!_disposed && request == _listOptionsRequest) {
        _listOptions = options;
        notifyListeners();
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
    return _listOptions;
  }

  /// Shows the lists as [options] and keeps them for the next launch.
  void changeListOptions(ListOptions options) {
    if (_disposed) return;
    _listOptionsRequest++;
    _listOptions = options;
    notifyListeners();
    unawaited(listOptionsSettings.save(options).catchError(reportError));
  }

  StreamSubscription<T> _watch<T>(_Live<T> live, Stream<T> stream) =>
      stream.listen(
        (value) {
          live
            ..value = value
            ..loaded = true
            ..error = null;
          if (live != _hidden && live != _covers) _phases.clear();
          if (live == _overview || live == _methods) _lastStyles = null;
          if (live != _hidden && live != _methods && live != _portions) {
            _data = null;
          }
          if (!_disposed) notifyListeners();
        },
        onError: (Object error, StackTrace stack) {
          reportError(error, stack);
          live
            ..loaded = true
            ..error = error;
          if (!_disposed) notifyListeners();
        },
      );

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// The latest value of one stream, and whether it has arrived or failed.
class _Live<T> {
  _Live(this.value);

  T value;
  bool loaded = false;
  Object? error;
}
