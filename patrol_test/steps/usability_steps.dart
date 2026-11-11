import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkUsability(PatrolIntegrationTester $, AppDatabase db) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Café Etiopía',
    roaster: 'Aurora',
    initialGrams: 250,
  );
  await repo.createCoffee(name: 'Colombia', roaster: 'Otro', initialGrams: 250);
  final method = await repo.createMethod(name: 'V60', category: 'pourover');
  final ids = <String>[];
  for (var i = 0; i < 2; i++) {
    ids.add(
      await repo.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 288,
        notes: 'Sweet, fruity and clear. ' * 20,
      ),
    );
  }
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: db),
      initialLocale: const Locale('en'),
    ),
  );
  Future<void> tab(String name) => $.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(name)),
  );
  Future<void> bottom() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await $.pumpAndSettle();
    final scroll = $.tester.state<ScrollableState>(
      verticalScrollable(find.byType(CoffeeForm)),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await $.pumpAndSettle();
  }

  await tab('Beans');
  await $.tap(find.text('Add bean'));
  await bottom();
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.text('This field is required'));
  await $.takeNativeScreenshot('usability-name-validation');
  await $.enterText(
    find.widgetWithText(TextFormField, 'Coffee name'),
    'Usability saved',
  );
  final price = find.widgetWithText(TextFormField, 'Paid price (€)');
  await $.tester.ensureVisible(price);
  await $.pumpAndSettle();
  await $.enterText(price, '12,345');
  await bottom();
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(price);
  expect(await repo.allCoffees(), hasLength(2));
  await $.takeNativeScreenshot('usability-price-validation');
  await $.enterText(price, '12,34');
  await bottom();
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.text('Bean saved'));
  expect(
    (await repo.allCoffees())
        .singleWhere((c) => c.name == 'Usability saved')
        .paidPriceCents,
    1234,
  );

  await tab('Brews');
  final search = find.byType(TextField).first;
  await $.enterText(search, 'no match');
  await $.tap(find.byTooltip('Clear search'));
  await $.enterText(search, 'etiopia');
  await $.waitUntilVisible(find.byKey(ValueKey('brew-card-${ids.last}')));
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $.tap(find.byKey(ValueKey('brew-card-${ids.last}')));
  await $.waitUntilVisible(find.byKey(const ValueKey('brew-detail-repeat')));
  await $.takeNativeScreenshot('usability-detail-actions');
  await $.tap(find.byKey(const ValueKey('brew-detail-compare')));
  await $.tap(find.byKey(ValueKey('compare-with-${ids.first}')));
  await $.waitUntilVisible(find.byType(BrewComparisonPage));
  await $.platformAutomator.android.pressBack();
  await $.tap(find.byKey(ValueKey('brew-card-${ids.last}')));
  await $.tap(find.byKey(const ValueKey('brew-detail-repeat')));
  await $.waitUntilVisible(find.byType(BrewForm));
  await $.tap(find.byKey(const ValueKey('brew-coffee-picker')));
  await $.tester.enterText(
    find.byKey(const ValueKey('brew-coffee-search')),
    'aurora',
  );
  await $.pumpAndSettle();
  await $.takeNativeScreenshot('usability-coffee-search-keyboard');
  await $.tap(find.byKey(ValueKey('coffee-choice-$coffee')));
  await $.tap(find.text('Cancel').last);
  if (find.byKey(const ValueKey('discard-changes')).evaluate().isNotEmpty) {
    await $.tap(find.byKey(const ValueKey('discard-changes')));
  }
  await $.tap(find.byKey(const ValueKey('history-filter-button')));
  final period = find.byKey(const ValueKey('history-period-week'));
  await $.tester.ensureVisible(period);
  await $.pumpAndSettle();
  await $.tap(period);
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('history-active-date')));
  await $.takeNativeScreenshot('usability-visible-date-filter');
  expect(await db.select(db.brews).get(), hasLength(2));
}
