import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Euros as the English UI shows them.
String formatEuro(double amount) => NumberFormat.currency(
  locale: 'en',
  name: 'EUR',
  symbol: '€',
  decimalDigits: 2,
).format(amount);

/// The test's own database file on the device.
Future<AppDatabase> openTestDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(path.join(directory.path, 'holybeans-patrol.sqlite'));
  return AppDatabase.forTesting(NativeDatabase.createInBackground(file));
}

/// Waits for the soft keyboard to open.
Future<void> waitForKeyboard(WidgetTester tester) async {
  for (
    var attempt = 0;
    attempt < 50 && tester.view.viewInsets.bottom <= 0;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.view.viewInsets.bottom, greaterThan(0));
}

/// Checks that each card starts inside the page list with a visible gap.
void expectCardsSeparated(
  WidgetTester tester,
  Finder pageList,
  Finder cards, {
  required int expectedCount,
}) {
  expect(pageList, findsOneWidget);
  final listCards = find.descendant(of: pageList, matching: cards);
  expect(listCards, findsNWidgets(expectedCount));
  final listBounds = tester.getRect(pageList);
  // Measure each card's surface, without its outer margin.
  final cardBounds = [
    for (var index = 0; index < expectedCount; index++)
      tester.getRect(
        find
            .descendant(
              of: listCards.at(index),
              matching: find.byType(Material),
            )
            .first,
      ),
  ];
  // Informative cards are tall, so only their tops must be on screen.
  for (final bounds in cardBounds) {
    expect(bounds.top, greaterThanOrEqualTo(listBounds.top));
    expect(bounds.top, lessThan(listBounds.bottom));
  }
  cardBounds.sort((a, b) => a.top.compareTo(b.top));
  for (var index = 1; index < cardBounds.length; index++) {
    expect(cardBounds[index].top, greaterThan(cardBounds[index - 1].bottom));
  }
}

/// The first vertical scrollable inside [within].
Finder verticalScrollable(Finder within) => find
    .descendant(
      of: within,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// Taps a slider at [fraction] of its track.
Future<void> tapSliderAt(WidgetTester tester, Finder slider, double fraction) {
  final bounds = tester.getRect(slider);
  return tester.tapAt(
    Offset(bounds.left + 16 + (bounds.width - 32) * fraction, bounds.center.dy),
  );
}

/// The page's list that holds [anchor].
Finder pageListContaining(Finder anchor) =>
    find.ancestor(of: anchor, matching: find.byType(ListView));

/// Empties the test database, which persists between runs.
Future<void> clearTestData(AppDatabase database) =>
    database.transaction(() async {
      await database.delete(database.pistonMethodLinks).go();
      await database.delete(database.pistonMeasurements).go();
      await database.delete(database.pistonMaintenances).go();
      await database.delete(database.pistonMachines).go();
      await database.delete(database.cafeDrinkPhotos).go();
      await database.delete(database.cafeDrinks).go();
      await database.delete(database.coffeeRoasterLinks).go();
      await database.delete(database.cafes).go();
      await database.delete(database.roasters).go();
      await database.delete(database.stockAdjustments).go();
      await database.delete(database.cuppingSessionCups).go();
      await database.delete(database.cuppingSessions).go();
      await database.delete(database.brewToolSelections).go();
      await database.delete(database.brews).go();
      await database.delete(database.waterProfiles).go();
      await database.delete(database.frozenPortions).go();
      await database.delete(database.coffeeLots).go();
      await database.delete(database.coffeeComponents).go();
      await database.delete(database.coffees).go();
      await database.delete(database.toolMethodLinks).go();
      await database.customStatement(
        'UPDATE method_tools SET merged_into_id = NULL',
      );
      await database.delete(database.methodTools).go();
      await database.delete(database.grinders).go();
      await database.delete(database.brewMethods).go();
      await database.delete(database.recipients).go();
      await database.delete(database.legacyPayloads).go();
      await database.delete(database.importRecords).go();
      await database.delete(database.appPreferences).go();
    });
