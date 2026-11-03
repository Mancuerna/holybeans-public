import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';
import 'package:holybeans/ui/stats/stats_page.dart';

Brew brew(
  String id,
  int day,
  double? grams, {
  String? grinder,
  bool preGround = false,
  bool archived = false,
}) => Brew(
  id: id,
  coffeeId: 'coffee',
  isPreGround: preGround,
  methodName: 'V60',
  grinderId: grinder,
  grinderName: grinder,
  doseGrams: grams,
  isFavorite: false,
  brewedAtMs: DateTime(2026, 9, day).millisecondsSinceEpoch,
  createdAtMs: 0,
  updatedAtMs: 0,
  archivedAtMs: archived ? 1 : null,
);

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets(
      'consumption follows the period, includes archived and shows gaps ($locale)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StatsPage(
              coffees: const [],
              components: const [],
              methods: const [],
              remainingGrams: 0,
              frozenGrams: 0,
              now: DateTime(2026, 9, 30),
              brews: [
                brew('old', 2, 1000, grinder: 'Old grinder'),
                brew('a', 24, 18, grinder: 'Comandante', archived: true),
                brew('b', 25, 12, grinder: 'Comandante'),
                brew('c', 26, null, grinder: 'Comandante'),
                brew('d', 28, 20, preGround: true),
                brew('e', 30, 10),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find
            .descendant(
              of: find.byKey(const ValueKey('stats-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        Future<void> reveal(Finder target) async {
          await tester.scrollUntilVisible(target, 180, scrollable: scroll);
          await tester.pumpAndSettle();
        }

        final chart = find.byKey(
          const ValueKey('stats-consumption-per-period'),
        );
        await reveal(chart);
        expect(
          tester
              .widget<StatsBarChart>(chart)
              .bars
              .fold(0.0, (sum, bar) => sum + bar.value),
          closeTo(1060, 1e-6),
        );
        await tester.tap(find.byKey(const ValueKey('stats-range-week')));
        await tester.pumpAndSettle();
        await reveal(chart);
        final bars = tester.widget<StatsBarChart>(chart).bars;
        expect(bars.map((bar) => bar.value), [
          18.0,
          12.0,
          0.0,
          0.0,
          20.0,
          0.0,
          10.0,
        ]);
        final paint = find
            .descendant(of: chart, matching: find.byType(CustomPaint))
            .first;
        await tester.ensureVisible(paint);
        final rect = tester.getRect(paint);
        await tester.tapAt(Offset(rect.left + rect.width / 14, rect.center.dy));
        await tester.pumpAndSettle();
        expect(find.textContaining('18 g'), findsOneWidget);
        await reveal(find.byKey(const ValueKey('stats-grinder-consumption')));
        expect(find.text('Comandante'), findsOneWidget);
        expect(find.text('30 g'), findsOneWidget);
        expect(
          find.text(
            locale == 'es'
                ? '2 de 3 preparaciones con dosis registrada'
                : '2 of 3 brews with a recorded dose',
          ),
          findsOneWidget,
        );
        expect(find.text('Old grinder'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
