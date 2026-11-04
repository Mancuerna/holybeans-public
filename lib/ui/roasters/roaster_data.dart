import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

List<RoasterProfile> roasterProfiles(
  JournalData data, {
  List<RoasterCafeDrink> cafeDrinks = const [],
}) => RoasterProfile.fromJournal(
  cafeDrinks: cafeDrinks,
  brewTotals: data.overview == null
      ? null
      : {
          for (final entry in data.overview!.byCoffee.entries)
            entry.key: (
              count: entry.value.count,
              rated: entry.value.rated,
              ratingSum: entry.value.ratingSum,
            ),
        },
  coffees: [
    for (final coffee in data.coffees)
      (
        id: coffee.id,
        name: coffee.name,
        roaster: coffee.roaster,
        paidPriceCents: coffee.paidPriceCents,
        rating: coffee.rating,
        archived: coffee.archivedAtMs != null,
      ),
  ],
  purchases: [
    for (final lot in data.lots)
      (
        coffeeId: lot.coffeeId,
        grams: lot.initialGrams,
        purchaseDate: lot.purchaseDate,
      ),
  ],
  brews: [
    for (final brew in data.brews)
      (coffeeId: brew.coffeeId, rating: brew.rating),
  ],
  origins: [
    for (final origin in data.components)
      (coffeeId: origin.coffeeId, country: origin.country),
  ],
);
