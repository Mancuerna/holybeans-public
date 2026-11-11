import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/stats/stats_page.dart';
import 'package:holybeans/ui/year_review/year_review_page.dart';
import 'package:holybeans/ui/year_review/year_review_share.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';
import 'package:intl/intl.dart';

import 'helpers/ui_test_support.dart';
import 'helpers/year_fixture.dart';

void main() {
  final now = DateTime(2026, 10, 13);
  final brews = [
    yearBrew('1', DateTime(2026, 2), dose: 18, rating: 9),
    yearBrew('2', DateTime(2026, 3), dose: 15, coffee: 'b'),
    yearBrew('old', DateTime(2025, 12, 31)),
  ];
  final coffees = [
    yearCoffee(
      'a',
      name: 'A very long coffee name from a beautiful farm in Colombia',
      paidPriceCents: 1250000,
    ),
    yearCoffee('b', paidPriceCents: 500),
  ];
  for (final language in ['es', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'year stories, change year and share preview: $language x$scale',
        (tester) async {
          final region = Locale(
            language == 'en' ? 'es' : 'en',
            language == 'en' ? 'ES' : 'GB',
          );
          tester.platformDispatcher.localeTestValue = region;
          addTearDown(tester.platformDispatcher.clearLocaleTestValue);
          tester.view.physicalSize = const Size(320, 760);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            localizedApp(
              locale: Locale(language),
              theme: ThemeData.dark(),
              home: YearReviewPage(
                lots: [
                  yearLot('a'),
                  yearLot('b', coffee: 'b'),
                ],
                brews: brews,
                coffees: coffees,
                components: yearComponents,
                methods: yearMethods,
                now: now,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final s = AppLocalizations.of(
            tester.element(find.byType(YearReviewPage)),
          )!;
          expect(
            find.text(
              s.yearReviewUntil(
                DateFormat.yMMMd(region.toString()).format(now),
              ),
            ),
            findsOneWidget,
          );
          expect(find.text(s.yearReviewIntro), findsOneWidget);
          await tester.drag(find.byType(PageView), const Offset(-300, 0));
          await tester.pumpAndSettle();
          expect(find.text(s.yearReviewOrigins), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('year-previous')));
          await tester.pumpAndSettle();
          expect(find.text(s.yearReviewIntro), findsOneWidget);
          for (var i = 0; i < 7; i++) {
            await tester.tap(find.byKey(const ValueKey('year-next')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'story ${i + 2}');
          }
          expect(find.text(s.yearReviewFinal), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('year-share')));
          await tester.pumpAndSettle();
          expect(find.text(s.yearReviewShareHint), findsOneWidget);
          expect(find.byType(YearExportCard), findsWidgets);
          expect(tester.takeException(), isNull);
          Navigator.of(
            tester.element(find.byKey(const ValueKey('year-share-confirm'))),
          ).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('year-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(s.yearReviewMoney));
          await tester.pumpAndSettle();
          for (final story in [
            YearStory.expensiveCoffee,
            YearStory.cheapCoffee,
            YearStory.expensiveCup,
            YearStory.cheapCup,
            YearStory.spending,
          ]) {
            await tester.tap(find.byType(DropdownButton<YearStory>));
            await tester.pumpAndSettle();
            await tester.tap(find.text(story.label(s)).last);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: story.name);
          }
          Navigator.of(tester.element(find.byType(DropdownButton<YearStory>)))
              .pop();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('year-selector')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('2025').last);
          await tester.pumpAndSettle();
          expect(find.text(s.yearReviewIntro), findsOneWidget);
          expect(find.text(s.yearReviewBrand), findsOneWidget);
          expect(find.text('1 / 7'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('statistics entry and empty journal can open and close', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: StatsPage(
          coffees: const [],
          brews: const [],
          components: const [],
          methods: const [],
          remainingGrams: 0,
          frozenGrams: 0,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-year-review')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.textContaining('No brews recorded'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
  });
  testWidgets('Stats forwards purchases and offers years without brews', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: StatsPage(
          coffees: [yearCoffee('a', paidPriceCents: 1500)],
          lots: [yearLot('a', purchased: '2023-02-01')],
          brews: const [],
          components: const [],
          methods: const [],
          remainingGrams: 0,
          frozenGrams: 0,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-year-review')));
    await tester.pumpAndSettle();
    expect(find.text('2023'), findsWidgets);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('year-next')));
    await tester.pumpAndSettle();
    expect(find.text('Your year,\nin euros.'), findsOneWidget);
    expect(find.textContaining('€15.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
