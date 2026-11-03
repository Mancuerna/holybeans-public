import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';
import 'package:patrol/patrol.dart';

import 'cupping_share_steps.dart';

Future<void> checkCupping(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final r = JournalRepository(database);
  final coffee = await r.createCoffee(
    name: 'Patrol cupping',
    roaster: 'Fixture',
    initialGrams: 250,
  );
  final lot = (await r.coffeeLots(coffee)).single.id;
  final g = await r.createGrinder(name: 'Patrol grinder');
  final w = await r.createWaterProfile(name: 'Patrol water');
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Equipment'),
    ),
  );
  await $.tap(find.byKey(const ValueKey('start-cupping')));
  await $.waitUntilVisible(find.byType(CuppingPage));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Session name (optional)'),
    'Patrol draft',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $.takeNativeScreenshot('cupping-shared-setup');
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-sessions')));
  final saved = (await r.watchCuppingSessions().first).single;
  expect(saved.name, 'Patrol draft');
  expect(await r.allBrews(), isEmpty);
  expect((await r.coffeeLot(lot))!.remainingGrams, 250);
  await $.tap(find.byKey(const ValueKey('cupping-sessions')));
  await $.tap(find.text('Patrol draft'));
  await $.waitUntilVisible(find.text('Patrol draft'));
  for (var i = 0; i < 2; i++) {
    final field = find.byKey(ValueKey('cupping-coffee-$i'));
    await $.scrollUntilVisible(finder: field);
    await $.tap(field);
    await $.tap(find.text('Patrol cupping (Fixture)').last);
  }
  await $.takeNativeScreenshot('cupping-cup-stock-setup');
  await $.tap(find.byKey(const ValueKey('cupping-pour')));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-countdown')));
  await $.takeNativeScreenshot('cupping-infusion-start');
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.text('Cupping sessions'));
  await r.discardCuppingDraft(saved.id);
  // Seed elapsed infusion, so the real-device test does not wait four minutes.
  final now = DateTime.now().millisecondsSinceEpoch;
  final d =
      CuppingDraft(
          cups: [
            for (var i = 0; i < 2; i++)
              CuppingCupDraft(coffeeId: coffee, lotId: lot)
                ..rating = 8
                ..scores = [1, 2, 3, 4, 5],
          ],
        )
        ..name = 'Patrol tasting'
        ..grinderId = g
        ..grindSetting = '20'
        ..waterProfileId = w
        ..startedAtMs = now - 721000
        ..phase = CuppingPhase.infusion
        ..sound = false;
  d.cups[1]
    ..commonWater = false
    ..waterProfileId = null;
  final id = await r.createCuppingSession(d);
  await $.waitUntilVisible(find.text('Patrol tasting'));
  await $.tap(find.text('Patrol tasting'));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-break')));
  await $.takeNativeScreenshot('cupping-crust-reminder');
  await $.tap(find.byKey(const ValueKey('cupping-break')));
  await $.tap(find.byKey(const ValueKey('cupping-taste')));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-finish')));
  await $.takeNativeScreenshot('cupping-by-cup');
  await $.tap(find.byKey(const ValueKey('cupping-view')));
  await $.takeNativeScreenshot('cupping-comparison');
  await $.tap(find.byKey(const ValueKey('cupping-finish')));
  await $.waitUntilVisible(find.text('Cupping saved'));
  expect(await r.allBrews(), hasLength(2));
  expect((await r.coffeeLot(lot))!.remainingGrams, 228);
  final links = await r.cuppingCups(id);
  expect((await r.brew(links[0].brewId))!.waterProfileId, w);
  expect((await r.brew(links[1].brewId))!.waterProfileId, null);
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.text('Patrol tasting'));
  await $.tap(find.text('Patrol tasting'));
  await $.waitUntilVisible(find.text('Cupping saved'));
  expect(find.byKey(const ValueKey('cupping-finish')), findsNothing);
  await $.takeNativeScreenshot('cupping-saved-session');
  await checkCuppingShare($, database);
}
