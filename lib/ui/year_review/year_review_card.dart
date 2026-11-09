import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/year_review/year_review_story.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';
import 'package:intl/intl.dart';

class YearStoryCard extends StatelessWidget {
  const YearStoryCard({
    super.key,
    required this.year,
    required this.story,
    this.forExport = false,
    this.photo,
  });
  final CoffeeYear year;
  final YearStory story;
  final bool forExport;
  final Widget? photo;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final locale = regionalLocale.toString();
    final number = NumberFormat.decimalPattern(locale);
    String n(num value) => number.format(value);
    final euros = NumberFormat.currency(locale: locale, symbol: '€');
    final color = switch (story) {
      YearStory.intro || YearStory.finalCard => yearLime,
      YearStory.origins || YearStory.best => yearLilac,
      YearStory.method ||
      YearStory.expensiveCoffee ||
      YearStory.expensiveCup => const Color(0xfff3bfa6),
      _ => yearPaper,
    };
    final title = switch (story) {
      YearStory.intro => s.yearReviewIntro,
      YearStory.origins => s.yearReviewOrigins,
      YearStory.roaster => s.yearReviewRoaster,
      YearStory.method => s.yearReviewMethod,
      YearStory.returning =>
        year.coffeeRanks.first.count > 1
            ? s.yearReviewReturn
            : s.yearReviewFirstCoffee,
      YearStory.best => s.yearReviewBest,
      YearStory.rhythm => s.yearReviewRhythm,
      YearStory.expensiveCoffee => s.yearMoneyExpensiveCoffee,
      YearStory.cheapCoffee => s.yearMoneyCheapCoffee,
      YearStory.expensiveCup => s.yearMoneyExpensiveCup,
      YearStory.cheapCup => s.yearMoneyCheapCup,
      YearStory.spending => s.yearMoneySpending,
      YearStory.finalCard => s.yearReviewFinal,
    };
    Widget caption(String text) => Text(
      text,
      style: const TextStyle(color: yearInk, fontSize: 15, height: 1.3),
    );
    Widget hero(String value, String label, {double size = 100}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: yearHeadline(size)),
        const SizedBox(height: 6),
        caption(label),
      ],
    );
    final body = <Widget>[];
    switch (story) {
      case YearStory.intro:
        body.add(hero(n(year.count), s.yearReviewBrews, size: 120));
        body.add(const SizedBox(height: 28));
        if (year.count == 0) {
          body.add(caption(s.yearReviewEmpty));
        } else {
          body.add(_YearTotals(year: year));
        }
      case YearStory.origins:
        body.add(hero(n(year.countries.length), s.yearReviewRecordedOrigins));
        body.add(const SizedBox(height: 24));
        body.add(
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final (index, country) in year.countries.take(6).indexed)
                Transform.rotate(
                  angle: index.isEven ? -.045 : .035,
                  child: YearBadge(
                    coffeeCountryFor(country.id)?.nameFor(s.localeName) ??
                        country.name,
                  ),
                ),
              if (year.countries.length > 6)
                YearBadge(s.yearReviewMoreOrigins(year.countries.length - 6)),
            ],
          ),
        );
      case YearStory.roaster:
      case YearStory.method:
      case YearStory.returning:
        final ranks = switch (story) {
          YearStory.roaster => year.roasters,
          YearStory.method => year.methodRanks,
          _ => year.coffeeRanks,
        };
        final first = ranks.first;
        final tied = ranks.length > 1 && ranks[1].count == first.count;
        final team =
            story == YearStory.method &&
            !tied &&
            first.count >= 3 &&
            first.count / year.count >= .6;
        body.add(
          Align(
            alignment: Alignment.centerLeft,
            child: YearBadge(tied ? s.yearReviewJointTop : '01', filled: true),
          ),
        );
        body.add(const SizedBox(height: 18));
        body.add(
          Text(
            team ? s.yearReviewTeam(first.name) : first.name,
            style: yearHeadline(team ? 64 : 48),
          ),
        );
        body.add(const SizedBox(height: 14));
        body.add(
          caption(
            s.yearReviewCountShare(
              first.count,
              n((first.count / year.count * 100).round()),
            ),
          ),
        );
        if (story != YearStory.returning && ranks.length > 1) {
          body.add(const SizedBox(height: 28));
          body.add(caption(s.yearReviewAlso));
          for (final rank in ranks.skip(1).take(2)) {
            body.add(const SizedBox(height: 8));
            body.add(Text(rank.name, style: yearHeadline(24)));
          }
        }
      case YearStory.best:
        final brew = year.rated.first;
        body.add(
          hero(
            '${NumberFormat('0.#', locale).format(brew.rating)} / 10',
            year.topRatingTies > 1
                ? s.yearReviewJointRating
                : s.yearReviewTopRating,
            size: 76,
          ),
        );
        body.add(const SizedBox(height: 20));
        body.add(
          Text(year.coffeeNames[brew.coffeeId] ?? '', style: yearHeadline(32)),
        );
        body.add(const SizedBox(height: 10));
        body.add(
          caption(
            [
              brew.methodName,
              DateFormat.MMMd(locale)
                  .format(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs)),
            ].where((part) => part.isNotEmpty).join(' · '),
          ),
        );
        if (photo != null && !forExport) {
          body.add(const SizedBox(height: 20));
          body.add(photo!);
        }
      case YearStory.rhythm:
        body.add(
          Text(
            DateFormat.MMMM(locale)
                .format(DateTime(year.year, year.explorerMonth)),
            style: yearHeadline(52),
          ),
        );
        body.add(const SizedBox(height: 8));
        body.add(
          caption(
            year.explorerTie ? s.yearReviewExplorerTie : s.yearReviewExplorer,
          ),
        );
        body.add(const SizedBox(height: 24));
        body.add(
          hero(
            n(year.monthlyCoffees[year.explorerMonth - 1]),
            s.yearReviewBeans,
            size: 70,
          ),
        );
        body.add(const SizedBox(height: 24));
        body.add(_MonthBars(year: year));
      case YearStory.expensiveCoffee:
      case YearStory.cheapCoffee:
        final price = story == YearStory.expensiveCoffee
            ? year.costs.coffeePrices.last
            : year.costs.coffeePrices.first;
        body.add(
          hero(euros.format(price.eurosPerKg), s.yearMoneyPerKg, size: 64),
        );
        body.add(const SizedBox(height: 24));
        body.add(
          Text(year.coffeeNames[price.coffeeId] ?? '', style: yearHeadline(36)),
        );
        if (year.costs.coffeeTies(price) > 1) {
          body.add(const SizedBox(height: 16));
          body.add(YearBadge(s.yearReviewTied));
        }
      case YearStory.expensiveCup:
      case YearStory.cheapCup:
        final cup = story == YearStory.expensiveCup
            ? year.costs.cups.last
            : year.costs.cups.first;
        body.add(
          hero(euros.format(cup.euros), s.yearReviewEstimatedCost, size: 72),
        );
        body.add(const SizedBox(height: 24));
        body.add(
          Text(
            year.coffeeNames[cup.brew.coffeeId] ?? '',
            style: yearHeadline(36),
          ),
        );
        body.add(const SizedBox(height: 12));
        body.add(caption(cup.brew.methodName));
        if (year.costs.cupTies(cup) > 1) {
          body.add(const SizedBox(height: 16));
          body.add(YearBadge(s.yearReviewTied));
        }
      case YearStory.spending:
        body.add(
          hero(
            euros.format(year.costs.totalEuros),
            s.yearReviewRecordedSpend,
            size: 72,
          ),
        );
      case YearStory.finalCard:
        body.add(hero(n(year.count), s.yearReviewBrews));
        body.add(const SizedBox(height: 22));
        body.add(_YearTotals(year: year));
        if (year.methodRanks.firstOrNull case final method?) {
          body.add(const SizedBox(height: 26));
          final tied =
              year.methodRanks.length > 1 &&
              year.methodRanks[1].count == method.count;
          body.add(
            caption(tied ? s.yearReviewJointTop : s.yearReviewTopMethod),
          );
          body.add(const SizedBox(height: 6));
          body.add(Text(method.name, style: yearHeadline(34)));
        }
        if (year.coffeeRanks.firstOrNull case final coffee?
            when coffee.name.isNotEmpty) {
          body.add(const SizedBox(height: 18));
          final tied =
              year.coffeeRanks.length > 1 &&
              year.coffeeRanks[1].count == coffee.count;
          body.add(
            caption(
              tied
                  ? '${s.yearReviewCardReturning} · ${s.yearReviewJointTop}'
                  : coffee.count > 1
                  ? s.yearReviewTopCoffee
                  : s.yearReviewCardReturning,
            ),
          );
          body.add(const SizedBox(height: 6));
          body.add(Text(coffee.name, style: yearHeadline(26)));
        }
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: yearHeadline(44)),
        const SizedBox(height: 28),
        ...body,
      ],
    );
    final header = Row(
      children: [
        const Icon(Icons.coffee_rounded, color: yearInk, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'HOLYBEANS',
            style: TextStyle(
              color: yearInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        Text('${year.year}', style: yearHeadline(22)),
      ],
    );
    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: yearInk, thickness: 1),
        const SizedBox(height: 6),
        Text(
          year.isPartial
              ? s.yearReviewUntil(DateFormat.yMMMd(locale).format(year.asOf))
              : s.yearReviewBrand,
          style: const TextStyle(color: yearInk, fontSize: 12),
        ),
      ],
    );
    return YearBackdrop(
      color: color,
      art: story.index,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          forExport ? 40 : 24,
          24,
          forExport ? 40 : 24,
        ),
        child: forExport
            ? Column(
                children: [
                  header,
                  const SizedBox(height: 22),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(width: 312, child: content),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  footer,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  header,
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: content,
                  ),
                  footer,
                ],
              ),
      ),
    );
  }
}

class _YearTotals extends StatelessWidget {
  const _YearTotals({required this.year});
  final CoffeeYear year;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final n = NumberFormat.decimalPattern(regionalLocale.toString());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: YearMetric(
            value: n.format(year.coffeeCount),
            label: s.yearReviewBeans,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: YearMetric(
            value: n.format(year.activeDays),
            label: s.yearReviewDays,
          ),
        ),
      ],
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.year});
  final CoffeeYear year;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final max = year.monthlyCoffees.reduce((a, b) => a > b ? a : b);
    final months = year.isPartial ? year.asOf.month : 12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < months; i++)
                Expanded(
                  child: Semantics(
                    label: s.yearReviewMonth(
                      DateFormat.MMMM(regionalLocale.toString())
                          .format(DateTime(year.year, i + 1)),
                      year.monthlyCoffees[i],
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: max == 0
                          ? 2
                          : 2 + 58 * year.monthlyCoffees[i] / max,
                      decoration: BoxDecoration(
                        color: i + 1 == year.explorerMonth
                            ? yearWine
                            : yearWine.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= months; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    '$i',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: yearInk),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
