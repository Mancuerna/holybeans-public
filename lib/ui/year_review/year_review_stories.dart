import 'package:flutter/material.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/domain/coffee_year_inputs.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/year_review/year_review_money.dart';
import 'package:holybeans/ui/year_review/year_review_share.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';
import 'package:intl/intl.dart';

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
  finalCard,
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
  if (year.costs.coffeePrices.isNotEmpty) ...[
    YearStory.expensiveCoffee,
    YearStory.cheapCoffee,
  ],
  if (year.costs.cups.isNotEmpty) ...[
    YearStory.expensiveCup,
    YearStory.cheapCup,
  ],
  if (year.costs.costedCoffees > 0) YearStory.spending,
  if (year.count > 0) YearStory.finalCard,
];

class YearStoryView extends StatelessWidget {
  const YearStoryView({
    super.key,
    required this.year,
    required this.story,
    this.photos,
    this.photoOf,
  });
  final CoffeeYear year;
  final YearStory story;
  final PhotoStore? photos;
  final Future<String?> Function(YearBrew)? photoOf;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat.decimalPattern(regionalLocale.toString());
    String n(num value) => number.format(value);
    final titles = {
      YearStory.intro: s.yearReviewIntro,
      YearStory.origins: s.yearReviewOrigins,
      YearStory.roaster: s.yearReviewRoaster,
      YearStory.method: s.yearReviewMethod,
      YearStory.returning: s.yearReviewReturn,
      YearStory.best: s.yearReviewBest,
      YearStory.rhythm: s.yearReviewRhythm,
      YearStory.expensiveCoffee: s.yearMoneyExpensiveCoffee,
      YearStory.cheapCoffee: s.yearMoneyCheapCoffee,
      YearStory.expensiveCup: s.yearMoneyExpensiveCup,
      YearStory.cheapCup: s.yearMoneyCheapCup,
      YearStory.spending: s.yearMoneySpending,
      YearStory.finalCard: s.yearReviewFinal,
    };
    final colors = [yearPaper, yearLime, yearLilac, const Color(0xfff3d8c4)];
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
    void big(String value, String label) => children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: yearHeadline(88)),
            Text(label, style: const TextStyle(fontSize: 18, color: yearInk)),
          ],
        ),
      ),
    );
    void ranks(List<YearRank> values) {
      for (final (index, rank) in values.take(3).indexed) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: yearHeadline(24).copyWith(color: yearWine),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rank.name,
                        style: yearHeadline(index == 0 ? 38 : 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.yearReviewCountShare(
                          rank.count,
                          n((rank.count / year.count * 100).round()),
                        ),
                        style: const TextStyle(color: yearInk),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: rank.count / year.count,
                        color: yearWine,
                        backgroundColor: yearInk.withValues(alpha: .08),
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (values.length > 1 && values[0].count == values[1].count) {
        text(s.yearReviewTied);
      }
    }

    switch (story) {
      case YearStory.intro:
        big(n(year.count), s.yearReviewBrews);
        if (year.count == 0) {
          text(s.yearReviewEmpty);
        } else {
          children.add(
            Wrap(
              spacing: 36,
              runSpacing: 20,
              children: [
                YearMetric(
                  value: n(year.coffeeCount),
                  label: s.yearReviewBeans,
                ),
                YearMetric(value: n(year.activeDays), label: s.yearReviewDays),
              ],
            ),
          );
          children.add(const SizedBox(height: 28));
          if (year.knownDoses > 0) {
            text(
              year.knownDoses == year.count
                  ? s.yearReviewDoseAll(n(year.doseGrams.round()))
                  : s.yearReviewDose(
                      n(year.doseGrams.round()),
                      year.knownDoses,
                      year.count,
                    ),
            );
          }
          text(s.yearReviewBasis);
        }
      case YearStory.origins:
        big(n(year.countries.length), s.yearReviewCountries);
        children.add(
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final country in year.countries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: yearPaper,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    coffeeCountryFor(country.id)?.nameFor(s.localeName) ??
                        country.name,
                    style: const TextStyle(
                      color: yearInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        );
        children.add(const SizedBox(height: 24));
        text(
          s.yearReviewOriginCoverage(year.coffeesWithOrigin, year.coffeeCount),
        );
      case YearStory.roaster:
        text(s.yearReviewRoasterBody);
        ranks(year.roasters);
      case YearStory.method:
        text(s.yearReviewMethodBody);
        ranks(year.methodRanks);
      case YearStory.returning:
        text(s.yearReviewReturnBody);
        ranks(year.coffeeRanks.take(1).toList());
        if (year.coffeeRanks.length > 1 &&
            year.coffeeRanks[0].count == year.coffeeRanks[1].count) {
          text(s.yearReviewTied);
        }
      case YearStory.best:
        final brew = year.rated.first;
        big(
          '${NumberFormat('0.#', regionalLocale.toString()).format(brew.rating)} / 10',
          '',
        );
        text(s.yearReviewBestBody(year.rated.length));
        children.add(
          Text(year.coffeeNames[brew.coffeeId] ?? '', style: yearHeadline(34)),
        );
        children.add(const SizedBox(height: 12));
        text(
          '${brew.methodName} · ${DateFormat.yMMMd(regionalLocale.toString()).format(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs))}',
        );
        if (year.topRatingTies > 1) {
          text(s.yearReviewBestTies(year.topRatingTies));
        }
        if (photos != null && photoOf != null) {
          children.add(
            _YearPhoto(
              key: ValueKey(brew.id),
              brew: brew,
              photos: photos!,
              photoOf: photoOf!,
            ),
          );
        }
      case YearStory.rhythm:
        final month = DateFormat.MMMM(regionalLocale.toString())
            .format(DateTime(year.year, year.explorerMonth));
        text(year.explorerTie ? s.yearReviewExplorerTie : s.yearReviewExplorer);
        children.add(
          Text(
            s.yearReviewMonth(
              month,
              year.monthlyCoffees[year.explorerMonth - 1],
            ),
            style: yearHeadline(36),
          ),
        );
        children.add(const SizedBox(height: 30));
        children.add(_MonthBars(year: year));
        children.add(const SizedBox(height: 22));
        text(s.yearReviewChartHint);
      case YearStory.expensiveCoffee:
      case YearStory.cheapCoffee:
      case YearStory.expensiveCup:
      case YearStory.cheapCup:
      case YearStory.spending:
        children.add(
          YearMoneyView(
            year: year,
            story: switch (story) {
              YearStory.expensiveCoffee => YearMoneyStory.expensiveCoffee,
              YearStory.cheapCoffee => YearMoneyStory.cheapCoffee,
              YearStory.expensiveCup => YearMoneyStory.expensiveCup,
              YearStory.cheapCup => YearMoneyStory.cheapCup,
              _ => YearMoneyStory.spending,
            },
          ),
        );
      case YearStory.finalCard:
        text(s.yearReviewFinalBody);
        children.add(
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              child: YearSummaryCard(year: year),
            ),
          ),
        );
        children.add(const SizedBox(height: 22));
        children.add(
          FilledButton.icon(
            key: const ValueKey('year-share'),
            style: FilledButton.styleFrom(
              backgroundColor: yearWine,
              foregroundColor: yearPaper,
            ),
            onPressed: () => shareCoffeeYear(context, year),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(s.yearReviewShare),
          ),
        );
    }
    return YearBackdrop(
      color: colors[story.index % colors.length],
      child: SingleChildScrollView(
        key: PageStorageKey('year-story-${year.year}-${story.name}'),
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${year.year} / HOLYBEANS',
              style: const TextStyle(
                color: yearWine,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(titles[story]!, style: yearHeadline(48)),
            const SizedBox(height: 32),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.year});
  final CoffeeYear year;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final max = year.monthlyBrews.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.yearReviewBrews, style: const TextStyle(color: yearInk)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      label: s.yearReviewMonthCount(
                        DateFormat.MMMM(regionalLocale.toString())
                            .format(DateTime(year.year, i + 1)),
                        year.monthlyBrews[i],
                      ),
                      child: Tooltip(
                        message: s.yearReviewMonthCount(
                          DateFormat.MMMM(regionalLocale.toString())
                              .format(DateTime(year.year, i + 1)),
                          year.monthlyBrews[i],
                        ),
                        child: FractionallySizedBox(
                          heightFactor: max == 0
                              ? 0
                              : year.monthlyBrews[i] / max,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: i + 1 == year.explorerMonth
                                  ? yearWine
                                  : yearWine.withValues(alpha: .35),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
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
            for (var i = 1; i <= 12; i++)
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

class _YearPhoto extends StatefulWidget {
  const _YearPhoto({
    super.key,
    required this.brew,
    required this.photos,
    required this.photoOf,
  });
  final YearBrew brew;
  final PhotoStore photos;
  final Future<String?> Function(YearBrew) photoOf;
  @override
  State<_YearPhoto> createState() => _YearPhotoState();
}

class _YearPhotoState extends State<_YearPhoto> {
  late final name = widget.photoOf(widget.brew);
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: name,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null || !PhotoStore.isValidName(file)) {
        return const SizedBox.shrink();
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.file(
          widget.photos.file(file),
          width: double.infinity,
          height: 230,
          fit: BoxFit.cover,
          cacheWidth: 800,
          semanticLabel: AppLocalizations.of(context)!.yearReviewPhoto,
          errorBuilder: (_, error, stack) => const SizedBox.shrink(),
        ),
      );
    },
  );
}
