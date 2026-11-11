import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkFlavorNotes(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  const oldProfile = 'Peach, JASMINE, durazno, lemon cake';
  final oldId = await repo.createCoffeeWithComponents(
    name: 'Imported profile',
    roaster: 'Fixture',
    components: const [],
    flavorProfile: oldProfile,
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
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.byKey(const ValueKey('bean-add-manual')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Coffee name'),
    'Patrol tags',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  final input = find.byKey(const ValueKey('coffee-flavor-profile'));
  await $.scrollUntilVisible(
    finder: input,
    view: verticalScrollable(find.byType(CoffeeForm)),
  );
  await $.enterText(input, 'Peach, Jazmín, personal note, ');
  expect(find.widgetWithText(InputChip, 'peach'), findsOneWidget);
  expect(find.widgetWithText(InputChip, 'jasmine'), findsOneWidget);
  await $.tap(input);
  await waitForKeyboard($.tester);
  await $.enterText(input, 'albar', hideKeyboard: false);
  await $.scrollUntilVisible(
    finder: find.widgetWithText(ActionChip, 'apricot'),
    view: verticalScrollable(find.byType(CoffeeForm)),
  );
  await $.takeNativeScreenshot('flavor-notes-suggestions-keyboard');
  await $.tap(find.widgetWithText(ActionChip, 'apricot'));
  await $.waitUntilVisible(find.widgetWithText(InputChip, 'apricot'));
  await $.takeNativeScreenshot('flavor-notes-editor');
  await $.tap(find.byTooltip('Remove personal note'));
  await $.enterText(input, 'Honey');
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $.tap(find.text('Cancel').last);
  await $.waitUntilVisible(find.byKey(const ValueKey('keep-editing')));
  await $.tap(find.byKey(const ValueKey('keep-editing')));
  expect($.tester.widget<TextFormField>(input).controller!.text, 'Honey');
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.text('Bean saved'));
  final created = (await database.select(database.coffees).get()).singleWhere(
    (coffee) => coffee.id != oldId,
  );
  expect(created.flavorProfile, 'peach, jasmine, apricot, honey');
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.byKey(ValueKey('bean-card-${created.id}')));
  await $.waitUntilVisible(find.byKey(const ValueKey('bean-detail-edit')));
  await $.takeNativeScreenshot('flavor-notes-details');
  await $.platformAutomator.android.pressBack();
  await $.tap(find.byKey(ValueKey('bean-card-$oldId')));
  await $.tap(find.byKey(const ValueKey('bean-detail-edit')));
  await $.scrollUntilVisible(
    finder: input,
    view: verticalScrollable(find.byType(CoffeeForm)),
  );
  expect(find.widgetWithText(InputChip, 'peach'), findsNWidgets(2));
  await $.takeNativeScreenshot('flavor-notes-imported-edit');
  await $.tap(find.text('Save').last);
  // Saving an edit started from the details goes back to them.
  await $.waitUntilVisible(find.byKey(const ValueKey('bean-detail-edit')));
  expect((await repo.coffee(oldId))!.flavorProfile, oldProfile);
}
