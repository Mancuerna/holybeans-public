import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/brew_rows_loader.dart';
import 'package:holybeans/ui/year_review/year_review_page.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';

class YearReviewEntry extends StatelessWidget {
  const YearReviewEntry({
    super.key,
    required this.brews,
    required this.coffees,
    required this.components,
    required this.methods,
    this.loadBrews,
    this.year,
    this.lots = const [],
    this.now,
    this.photos,
    this.photoOf,
  });
  final List<CoffeeLot> lots;
  final List<Brew> brews;
  final Future<List<Brew>> Function()? loadBrews;
  final List<Coffee> coffees;
  final List<CoffeeComponent> components;
  final List<BrewMethod> methods;
  final int? year;
  final DateTime? now;
  final PhotoStore? photos;
  final Future<String?> Function(Brew)? photoOf;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Card(
      color: yearLime,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const ValueKey('open-year-review'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: const Icon(Icons.auto_awesome_rounded, color: yearWine),
        title: Text(
          s.yearReviewTitle,
          style: const TextStyle(color: yearInk, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          year == null ? s.yearReviewEntry : s.yearReviewSeason(year!),
          style: const TextStyle(color: yearInk),
        ),
        trailing: const Icon(Icons.arrow_forward_rounded, color: yearWine),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => loadBrews == null
                ? _page(brews)
                : BrewRowsLoader(load: loadBrews!, builder: _page),
          ),
        ),
      ),
    );
  }

  Widget _page(List<Brew> rows) => YearReviewPage(
    lots: lots,
    brews: rows,
    coffees: coffees,
    components: components,
    methods: methods,
    initialYear: year,
    now: now,
    photos: photos,
    photoOf: photoOf,
  );
}
