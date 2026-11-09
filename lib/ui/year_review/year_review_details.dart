import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

Future<void> showYearDetails(BuildContext context, CoffeeYear year) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: _YearDetails(year: year),
        ),
      ),
    );

class _YearDetails extends StatelessWidget {
  const _YearDetails({required this.year});
  final CoffeeYear year;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final n = NumberFormat.decimalPattern(regionalLocale.toString());
    final euros = NumberFormat.currency(
      locale: regionalLocale.toString(),
      symbol: '€',
    );
    final costs = year.costs;
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(text));
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Text(
          s.yearReviewAbout,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        title(s.yearReviewTitle),
        note(s.yearReviewBasis),
        if (year.knownDoses > 0)
          note(
            s.yearReviewDose(
              n.format(year.doseGrams.round()),
              year.knownDoses,
              year.count,
            ),
          ),
        if (year.countries.isNotEmpty) ...[
          title(s.yearReviewCardOrigins),
          note(
            s.yearReviewOriginCoverage(
              year.coffeesWithOrigin,
              year.coffeeCount,
            ),
          ),
          note(
            year.countries
                .map(
                  (country) =>
                      coffeeCountryFor(country.id)?.nameFor(s.localeName) ??
                      country.name,
                )
                .join(' · '),
          ),
        ],
        if (year.rated.isNotEmpty) ...[
          title(s.yearReviewCardBest),
          note(s.yearReviewBestBody(year.rated.length)),
          if (year.topRatingTies > 1)
            note(s.yearReviewBestTies(year.topRatingTies)),
        ],
        if (costs.costedCoffees > 0 || costs.cups.isNotEmpty) ...[
          title(s.yearReviewMoney),
          note(s.yearMoneyCoffeeBasis),
          note(
            s.yearMoneyPurchaseCoverage(
              costs.costedCoffees,
              costs.purchasedCoffees,
            ),
          ),
          if (costs.estimatedDateCoffees > 0)
            note(s.yearMoneyDateFallback(costs.estimatedDateCoffees)),
          note(s.yearMoneyCupBasis(costs.cups.length, costs.brewCount)),
          note(s.yearMoneySpendingBasis),
          title(s.yearMoneyMonthly),
          for (var i = 0; i < (year.isPartial ? year.asOf.month : 12); i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                DateFormat.MMMM(regionalLocale.toString())
                    .format(DateTime(year.year, i + 1)),
              ),
              trailing: Text(euros.format(costs.monthlyEuros[i])),
            ),
        ],
      ],
    );
  }
}
