import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';
import 'package:intl/intl.dart';

enum YearMoneyStory {
  expensiveCoffee,
  cheapCoffee,
  expensiveCup,
  cheapCup,
  spending,
}

class YearMoneyView extends StatelessWidget {
  const YearMoneyView({super.key, required this.year, required this.story});
  final CoffeeYear year;
  final YearMoneyStory story;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final costs = year.costs;
    final euros = NumberFormat.currency(
      locale: regionalLocale.toString(),
      symbol: '€',
    );
    final children = <Widget>[];
    void text(String value) => children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(
          value,
          style: const TextStyle(fontSize: 17, height: 1.5, color: yearInk),
        ),
      ),
    );
    void amount(double value, String label) {
      children.add(
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(euros.format(value), style: yearHeadline(64)),
          ),
        ),
      );
      text(label);
    }

    void coffee(String id) => children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(year.coffeeNames[id] ?? '', style: yearHeadline(34)),
      ),
    );
    void purchaseBasis() {
      text(
        s.yearMoneyPurchaseCoverage(
          costs.costedCoffees,
          costs.purchasedCoffees,
        ),
      );
      if (costs.estimatedDateCoffees > 0) {
        text(s.yearMoneyDateFallback(costs.estimatedDateCoffees));
      }
    }

    switch (story) {
      case YearMoneyStory.expensiveCoffee:
      case YearMoneyStory.cheapCoffee:
        final price = story == YearMoneyStory.expensiveCoffee
            ? costs.coffeePrices.last
            : costs.coffeePrices.first;
        amount(price.eurosPerKg, s.yearMoneyPerKg);
        coffee(price.coffeeId);
        text(s.yearMoneyCoffeeBasis);
        if (costs.coffeeTies(price) > 1) {
          text(s.yearMoneyTies(costs.coffeeTies(price)));
        }
        purchaseBasis();
      case YearMoneyStory.expensiveCup:
      case YearMoneyStory.cheapCup:
        final cup = story == YearMoneyStory.expensiveCup
            ? costs.cups.last
            : costs.cups.first;
        amount(cup.euros, s.yearMoneyPerCup);
        coffee(cup.brew.coffeeId);
        final date = DateFormat.yMMMd(regionalLocale.toString())
            .format(DateTime.fromMillisecondsSinceEpoch(cup.brew.brewedAtMs));
        text(
          [
            cup.brew.methodName,
            date,
          ].where((part) => part.isNotEmpty).join(', '),
        );
        text(
          s.yearMoneyDose(
            NumberFormat(
              '0.##',
              regionalLocale.toString(),
            ).format(cup.brew.doseGrams),
          ),
        );
        if (costs.cupTies(cup) > 1) text(s.yearMoneyTies(costs.cupTies(cup)));
        text(s.yearMoneyCupBasis(costs.cups.length, costs.brewCount));
      case YearMoneyStory.spending:
        amount(costs.totalEuros, s.yearMoneyAnnual);
        text(s.yearMoneySpendingBasis);
        purchaseBasis();
        children.add(const SizedBox(height: 10));
        children.add(Text(s.yearMoneyMonthly, style: yearHeadline(28)));
        children.add(const SizedBox(height: 18));
        final max = costs.monthlyEuros.reduce((a, b) => a > b ? a : b);
        final months = year.isPartial ? year.asOf.month : 12;
        for (var i = 0; i < months; i++) {
          final month = DateFormat.MMMM(regionalLocale.toString())
              .format(DateTime(year.year, i + 1));
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(month, style: const TextStyle(color: yearInk)),
                      Text(
                        euros.format(costs.monthlyEuros[i]),
                        style: const TextStyle(
                          color: yearWine,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: max == 0 ? 0 : costs.monthlyEuros[i] / max,
                    color: yearWine,
                    backgroundColor: yearInk.withValues(alpha: .08),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          );
        }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
