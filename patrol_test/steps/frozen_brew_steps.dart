import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// Cancelling keeps frozen stock; saving and deleting restore its real origin.
Future<void> checkFrozenBrewDeletion(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffeeWithComponents(
    name: 'Frozen origin',
    roaster: 'Patrol',
    components: const [],
    initialGrams: 100,
    freeze: const FreezeRequest(grams: 100, frozenDate: '2026-09-20'),
  );
  final lot = (await repository.coffeeLots(coffee)).single.id;
  final original = (await repository.frozenPortionsForLot(lot)).single;
  await repository.createMethod(name: 'V60', category: 'pourover');
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
  await $.tap(find.text('Frozen (1)'));

  Future<void> openFrozenBrew() async {
    await $.tap(find.text('Frozen origin'));
    final brew = find.byKey(const ValueKey('brew-with-bean-button'));
    await $.scrollUntilVisible(
      finder: brew,
      view: verticalScrollable(find.byType(BottomSheet)),
    );
    await $.tap(brew);
    await $.enterText(find.byKey(const ValueKey('thaw-grams')), '18');
    await $.tap(find.byKey(const ValueKey('thaw-confirm')));
    await $.tap(find.text('Choose a method'));
    await $.tap(find.text('V60').last);
    final notice = find.byKey(const ValueKey('brew-thaw-on-save'));
    await $.scrollUntilVisible(
      finder: notice,
      view: verticalScrollable(find.byType(BrewForm)),
    );
    await $.waitUntilVisible(notice);
  }

  await openFrozenBrew();
  expect(
    (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
    100,
  );
  expect((await repository.coffeeLot(lot))!.remainingGrams, 0);
  await $.takeNativeScreenshot('frozen-brew-pending-thaw');
  await $.tap(find.text('Cancel').last);
  await $.tap(find.byKey(const ValueKey('discard-changes')));
  expect(
    (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
    100,
  );

  await openFrozenBrew();
  await $.tap(find.widgetWithText(FilledButton, 'Save').last);
  await $.waitUntilVisible(find.text('Brew saved'));
  final saved = await database.select(database.brews).getSingle();
  expect((saved.frozenPortionId, saved.frozenDoseGrams), (original.id, 18));
  expect(
    (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
    82,
  );
  expect((await repository.coffeeLot(lot))!.remainingGrams, 0);

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byKey(ValueKey('brew-card-${saved.id}')),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await $.tap(find.byKey(ValueKey('brew-delete-${saved.id}')));
  await $.waitUntilVisible(
    find.textContaining('go back to frozen portion ${original.label}'),
  );
  await $.takeNativeScreenshot('delete-brew-frozen-origin');
  await $.tap(find.text('Cancel'));
  expect(await repository.brew(saved.id), isNotNull);
  await $.tap(
    find.descendant(
      of: find.byKey(ValueKey('brew-card-${saved.id}')),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await $.tap(find.byKey(ValueKey('brew-delete-${saved.id}')));
  await $.tap(find.byKey(const ValueKey('delete-brew-confirm')));
  await $.waitUntilVisible(find.text('Brew deleted'));
  final restored = (await repository.frozenPortionsForLot(lot)).single;
  expect(
    (restored.id, restored.label, restored.frozenDate, restored.remainingGrams),
    (original.id, original.label, original.frozenDate, 100),
  );
  expect((await repository.coffeeLot(lot))!.remainingGrams, 0);
  expect(await repository.brew(saved.id), isNull);

  // Direct Brew asks for its frozen source, and cancelling preserves stock.
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Home'),
    ),
  );
  await $.tap(find.text('Brew'));
  await $.tap(find.text('Choose a method'));
  await $.tap(find.text('V60').last);
  final dose = find.widgetWithText(TextFormField, 'Dose (g)');
  await $.scrollUntilVisible(
    finder: dose,
    view: verticalScrollable(find.byType(BrewForm)),
  );
  await $.enterText(dose, '90');
  await $.tap(find.widgetWithText(FilledButton, 'Save').last);
  await $.waitUntilVisible(find.byKey(const ValueKey('brew-choose-frozen')));
  await $.tap(find.text('Cancel').last);
  expect(await repository.allBrews(), isEmpty);
  expect(
    (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
    100,
  );
  await $.tap(find.widgetWithText(FilledButton, 'Save').last);
  await $.tap(find.byKey(ValueKey('brew-frozen-${original.id}')));
  await $.waitUntilVisible(find.byKey(const ValueKey('coffee-archive-dialog')));
  final direct = await database.select(database.brews).getSingle();
  expect((await repository.coffeeLot(lot))!.overdrawGrams ?? 0, 0);
  expect(direct.frozenPortionId, original.id);
  await $.pumpAndSettle();
  await $.waitUntilVisible(find.byKey(const ValueKey('coffee-archive-dialog')));
  expect(find.textContaining('There are 10 g left'), findsOneWidget);
  await $.takeNativeScreenshot('frozen-low-stock-archive-offer');
  await $.tap(find.text('Cancel').last);
  expect((await repository.coffee(coffee))!.archivedAtMs, isNull);
  expect(
    (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
    10,
  );
  await $.takeNativeScreenshot('direct-brew-frozen-stock');
  await repository.deleteBrew(direct.id);
  final bulk = await repository.createCoffee(
    name: 'Bulk freezer',
    roaster: 'Patrol',
    initialGrams: 950,
  );
  final bulkLot = (await repository.coffeeLots(bulk)).single.id;
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Available (1)'));
  await $.tap(find.text('Bulk freezer'));
  final freeze = find.byKey(const ValueKey('freeze-coffee-button'));
  await $.scrollUntilVisible(
    finder: freeze,
    view: verticalScrollable(find.byType(BottomSheet)),
  );
  await $.tap(freeze);
  await $.enterText(find.byKey(const ValueKey('freeze-grams')), '950');
  await $.tap(find.byKey(const ValueKey('freeze-split')));
  await $.waitUntilVisible(find.text('Create 9 portions of 100 g.'));
  final remainder = find.byKey(const ValueKey('freeze-remainder'));
  await $.scrollUntilVisible(
    finder: remainder,
    view: verticalScrollable(find.byType(BottomSheet).last),
  );
  await $.tap(remainder);
  await $.takeNativeScreenshot('bulk-freeze-remainder');
  final freezeSave = find.byKey(const ValueKey('freeze-save'));
  await $.scrollUntilVisible(
    finder: freezeSave,
    view: verticalScrollable(find.byType(BottomSheet).last),
  );
  await $.tap(freezeSave);
  // The snackbar belongs to the page underneath the still-open detail sheet.
  expect(find.textContaining('Froze 9 portions'), findsOneWidget);
  final batch = await repository.frozenPortionsForLot(bulkLot);
  expect(batch, hasLength(9));
  expect(batch.every((p) => p.remainingGrams == 100), isTrue);
  expect(batch.map((p) => p.label).toSet(), hasLength(9));
  expect((await repository.coffeeLot(bulkLot))!.remainingGrams, 50);
  await $.scrollUntilVisible(
    finder: find.text(batch.first.label),
    view: verticalScrollable(find.byType(BottomSheet)),
  );
  await $.waitUntilVisible(find.text(batch.first.label));
  await $.takeNativeScreenshot('bulk-freeze-saved');
}
