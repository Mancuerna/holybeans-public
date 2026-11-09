import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';

enum YearStory {
  intro,
  origins,
  roaster,
  method,
  returning,
  best,
  rhythm,
  expensiveCoffee,
  cheapCoffee,
  expensiveCup,
  cheapCup,
  spending,
  finalCard;

  String label(AppLocalizations s) => switch (this) {
    intro => s.yearReviewCardIntro,
    origins => s.yearReviewCardOrigins,
    roaster => s.yearReviewCardRoaster,
    method => s.yearReviewCardMethod,
    returning => s.yearReviewCardReturning,
    best => s.yearReviewCardBest,
    rhythm => s.yearReviewCardRhythm,
    expensiveCoffee => s.yearMoneyExpensiveCoffee.replaceAll('\n', ' '),
    cheapCoffee => s.yearMoneyCheapCoffee.replaceAll('\n', ' '),
    expensiveCup => s.yearMoneyExpensiveCup.replaceAll('\n', ' '),
    cheapCup => s.yearMoneyCheapCup.replaceAll('\n', ' '),
    spending => s.yearReviewMoney,
    finalCard => s.yearReviewCardFinal,
  };
}

List<YearStory> storiesFor(CoffeeYear year) => [
  YearStory.intro,
  if (year.countries.isNotEmpty) YearStory.origins,
  if (year.roasters.isNotEmpty) YearStory.roaster,
  if (year.methodRanks.isNotEmpty) YearStory.method,
  if (year.coffeeRanks.firstOrNull?.name.isNotEmpty ?? false)
    YearStory.returning,
  if (year.rated.isNotEmpty) YearStory.best,
  if (year.count > 0) YearStory.rhythm,
  if (year.count == 0 && year.costs.costedCoffees > 0) YearStory.spending,
  if (year.count > 0) YearStory.finalCard,
];

List<YearStory> moneyStoriesFor(CoffeeYear year) => [
  if (year.costs.coffeePrices.isNotEmpty) ...[
    YearStory.expensiveCoffee,
    YearStory.cheapCoffee,
  ],
  if (year.costs.cups.isNotEmpty) ...[
    YearStory.expensiveCup,
    YearStory.cheapCup,
  ],
  if (year.costs.costedCoffees > 0) YearStory.spending,
];
