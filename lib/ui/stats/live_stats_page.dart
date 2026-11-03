import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/stats/stats_page.dart';

/// Stats kept up to date while open (e.g. after rating a brew from a
/// reminder); the lists at hand fill it until the queries answer.
class LiveStatsPage extends StatefulWidget {
  const LiveStatsPage({
    super.key,
    required this.actions,
    required this.coffees,
    required this.brews,
    required this.lots,
    required this.components,
  });

  final JournalActions actions;
  final List<Coffee> coffees;
  final List<Brew> brews;
  final List<CoffeeLot> lots;
  final List<CoffeeComponent> components;

  @override
  State<LiveStatsPage> createState() => _LiveStatsPageState();
}

class _LiveStatsPageState extends State<LiveStatsPage> {
  late final _coffees = widget.actions.repository.watchCoffees(
    includeArchived: true,
  );
  late final _brews = widget.actions.repository.watchBrews(
    includeArchived: true,
  );
  late final _lots = widget.actions.repository.watchLots();

  /// Grams of the coffees still in use: a finished coffee's leftovers are
  /// not stock, as on Home.
  static double _total(Map<String, double> grams, List<Coffee> coffees) {
    final active = {
      for (final coffee in coffees)
        if (coffee.archivedAtMs == null) coffee.id,
    };
    return grams.entries
        .where((entry) => active.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Coffee>>(
    stream: _coffees,
    initialData: widget.coffees,
    builder: (context, coffeeSnapshot) => StreamBuilder<List<Brew>>(
      stream: _brews,
      initialData: widget.brews,
      builder: (context, brewSnapshot) => StreamBuilder<List<CoffeeLot>>(
        stream: _lots,
        initialData: widget.lots,
        builder: (context, lotSnapshot) {
          final coffees = coffeeSnapshot.data ?? widget.coffees;
          final lots = lotSnapshot.data ?? widget.lots;
          return StatsPage(
            photos: widget.actions.photos,
            photoOf: (brew) async =>
                (await widget.actions.repository.brewPhotos(brew.id))
                    .firstOrNull ??
                (await widget.actions.repository.coffeePhotos(brew.coffeeId))
                    .firstOrNull,
            coffees: coffees,
            brews: brewSnapshot.data ?? widget.brews,
            components: widget.components,
            methods: widget.actions.methods,
            lots: lots,
            pricePerKg: pricePerKgByCoffee(coffees, lots),
            remainingGrams: _total(unfrozenGramsByCoffee(lots), coffees),
            frozenGrams: _total(
              frozenGramsByCoffee(lots, widget.actions.portions),
              coffees,
            ),
          );
        },
      ),
    ),
  );
}
