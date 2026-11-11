import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// Marks an older brew as the favourite recipe from its details and checks
/// that a new brew of that coffee and method starts from it, not from the
/// latest one.
Future<void> checkFavoriteRecipe(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Favourite bean',
    roaster: 'Test',
  );
  final method = await repository.createMethod(
    name: 'Favourite V60',
    category: 'pourover',
  );
  final best = await repository.createBrew(
    coffeeId: coffee,
    methodName: 'Favourite V60',
    methodId: method,
    grindSetting: '20 clicks',
    doseGrams: 15,
    waterGrams: 250,
    brewedAt: DateTime.now().subtract(const Duration(days: 2)),
  );
  await repository.createBrew(
    coffeeId: coffee,
    methodName: 'Favourite V60',
    methodId: method,
    grindSetting: '26 clicks',
    doseGrams: 18,
    brewedAt: DateTime.now().subtract(const Duration(hours: 3)),
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  final card = find.byKey(ValueKey('brew-card-$best'));
  await $.scrollUntilVisible(finder: card);
  await $.tap(card);
  await $.tap(find.byKey(const ValueKey('brew-detail-favorite')));
  await $.waitUntilVisible(
    find.byKey(const ValueKey('brew-detail-favorite-note')),
  );
  await $.takeNativeScreenshot('brew-favorite-marked');
  expect((await repository.brew(best))!.isFavorite, isTrue);
  await $.platform.android.pressBack();
  await $.pumpAndSettle();
  await $.waitUntilVisible(find.byKey(ValueKey('brew-favorite-$best')));

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Favourite bean'));
  await $.scrollUntilVisible(
    finder: find.text('Brew with this bean'),
    view: verticalScrollable(find.byType(BottomSheet).last),
  );
  await $.tap(find.text('Brew with this bean'));
  final form = verticalScrollable(find.byType(BrewForm));
  final methodField = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Choose a method',
  );
  await $.scrollUntilVisible(finder: methodField, view: form);
  await $.tap(methodField);
  await $.tap(find.text('Favourite V60').last);
  await $.waitUntilVisible(
    find.textContaining('Your favourite recipe with this coffee'),
  );
  await $.takeNativeScreenshot('brew-form-favorite');
  final grind = find.widgetWithText(TextFormField, 'Grind setting');
  await $.scrollUntilVisible(finder: grind, view: form);
  expect($.tester.widget<TextFormField>(grind).controller!.text, '20 clicks');
  await $.tap(find.text('Cancel').last);
  await $.tap(find.byKey(const ValueKey('discard-changes')));
}
