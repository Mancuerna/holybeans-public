import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/stats_comparison.dart';
import 'package:holybeans/ui/stats/stats_data.dart';

typedef StatsRequest = ({
  List<Brew> brews,
  List<Coffee> coffees,
  List<CoffeeComponent> components,
  List<BrewMethod> methods,
  List<CoffeeLot> lots,
  Map<String, double> prices,
  StatsRange range,
  DateTime now,
  String language,
  double remaining,
  double frozen,
});

StatsData prepareStats(StatsRequest input) {
  final (
    :brews,
    :coffees,
    :components,
    :methods,
    :lots,
    :prices,
    :range,
    :now,
    :language,
    :remaining,
    :frozen,
  ) = input;
  BrewStats statsFor(List<Brew> rows, DateTime at) => BrewStats.compute(
    brews: rows,
    coffees: coffees,
    components: components,
    styleOf: (brew) => brewStyleOf(brew, methods),
    range: range,
    now: at,
    languageCode: language,
    pricePerKg: prices,
  );
  final before = previousPeriod(
    brews,
    range,
    now,
    brewedAtMs: (brew) => brew.brewedAtMs,
  );
  return StatsData(
    stats: statsFor(brews, now),
    previous: before == null ? null : statsFor(before.brews, before.now),
    range: range,
    now: now,
    allBrews: brews,
    coffees: coffees,
    lots: lots,
    pricePerKg: prices,
    styleOf: (brew) => brewStyleOf(brew, methods),
    remainingGrams: remaining,
    frozenGrams: frozen,
  )..prepareInsights();
}

class StatsViewModel extends ChangeNotifier {
  StatsRequest? _input;
  StatsRequest? _pending;
  bool _running = false;
  bool _disposed = false;
  StatsData? value;
  Object? error;

  void update(StatsRequest request) {
    if (_disposed || request == _input) return;
    _input = request;
    error = null;
    if (request.brews.length <= 200) {
      _pending = null;
      value = prepareStats(request);
      notifyListeners();
    } else {
      value = null;
      _pending = request;
      notifyListeners();
      if (!_running) unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending != null) {
        final request = _pending!;
        _pending = null;
        try {
          final result = await compute(
            prepareStats,
            request,
            debugLabel: 'journal-statistics',
          );
          if (_disposed || request != _input) continue;
          value = result;
          notifyListeners();
        } catch (failure, stack) {
          if (_disposed || request != _input) continue;
          reportError(failure, stack);
          error = failure;
          notifyListeners();
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = _input = null;
    value = null;
    super.dispose();
  }
}
