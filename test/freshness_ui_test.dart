import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';

String _isoDaysAgo(int days) => DateTime.now()
    .subtract(Duration(days: days))
    .toIso8601String()
    .substring(0, 10);

void main() {
  testWidgets('bean details show freshness phases and a sweet spot', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = JournalRepository(database);
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    // A light roast 20 days old, opened 19 days ago with the first brew:
    // the open days count 1.7 times, so it is effectively on day 33, past
    // its prime for filter (days 8–25) but still good (until 36).
    final coffeeId = await repository.createCoffee(
      name: 'Fresh light',
      roaster: 'Test roaster',
      roastLevel: 'light',
      roastDate: _isoDaysAgo(20),
      initialGrams: 500,
    );
    final lotId = (await repository.coffeeLots(coffeeId)).single.id;
    // Rated brews: best around effective days 20–23, smoothed to 18–25.
    for (final (daysAgo, rating) in [
      (19, 5.0),
      (18, 5.5),
      (8, 9.0),
      (7, 8.5),
      (6, 9.0),
      (1, 6.0),
      (0, 6.5),
    ]) {
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lotId,
        methodId: methodId,
        methodName: 'V60',
        doseGrams: 15,
        rating: rating,
        brewedAt: DateTime.now().subtract(Duration(days: daysAgo)),
      );
    }

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('bean-freshness-$coffeeId')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Freshness: Good, Filter',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Fresh light'));
    await tester.pumpAndSettle();
    final section = find.byKey(const ValueKey('freshness-section'));
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('freshness-filter')),
        matching: find.text('Good'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Estimated age: 33 days. Based on roast level. '
        'Bag opened 19 days ago, ages faster',
      ),
      findsOneWidget,
    );
    final chart = find.byKey(const ValueKey('rating-by-age'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Ratings by estimated age. 7 rated brews between days '
                    '1 and 33; best 9 on day 20',
      ),
      findsOneWidget,
    );
    final sweetSpot = find.byKey(const ValueKey('sweet-spot-filter'));
    expect(sweetSpot, findsOneWidget);
    expect(
      find.descendant(
        of: sweetSpot,
        matching: find.textContaining(
          'Filter, days 18–25: around 8.8 across 3 brews',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
