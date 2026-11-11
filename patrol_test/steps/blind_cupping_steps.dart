import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';
import 'package:patrol/patrol.dart';

Future<void> checkBlindCupping(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final r = JournalRepository(db);
  final coffee = await r.createCoffee(
    name: 'Blind Kenya',
    roaster: 'Fixture',
    initialGrams: 100,
  );
  final lot = (await r.coffeeLots(coffee)).single.id;
  final portion = await r.freezeCoffee(
    lotId: lot,
    grams: 50,
    frozenDate: '2026-10-09',
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: db),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Equipment'),
    ),
  );
  await $.tap(find.byKey(const ValueKey('start-cupping')));
  await $.tap(find.byKey(const ValueKey('cupping-blind')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Session name (optional)'),
    'Patrol blind',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  expect(find.byKey(const ValueKey('cupping-coffee-0')), findsNothing);
  expect(find.textContaining('Blind Kenya'), findsNothing);
  await $.takeNativeScreenshot('blind-cupping-setup');
  await $.tap(find.byKey(const ValueKey('cupping-pour')));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-countdown')));
  expect(find.text('Cup A'), findsOneWidget);
  expect(find.textContaining('Blind Kenya'), findsNothing);
  await $.takeNativeScreenshot('blind-cupping-clock');
  await $.tap(find.byKey(const ValueKey('cupping-pause')));
  expect(find.text('Resume'), findsOneWidget);
  await $.tap(find.byKey(const ValueKey('cupping-reset-clock')));
  expect(find.text('Pause'), findsOneWidget);
  await $.platformAutomator.android.pressBack();
  await $.tap(find.byKey(const ValueKey('cupping-sessions')));
  final row = (await r.watchCuppingSessions().first).single;
  final d = CuppingDraft.fromJson(row.draftJson);
  expect(d.blind, true);
  expect(await r.allBrews(), isEmpty);
  final now = DateTime.now().millisecondsSinceEpoch;
  d.startedAtMs = now - 721000;
  d.brokenAtMs = now - 481000;
  d.tastingAtMs = now;
  d.phase = CuppingPhase.tasting;
  d.sound = false;
  for (var i = 0; i < d.cups.length; i++) {
    d.cups[i].rating = i == 0 ? 0 : 8.5;
    d.cups[i].scores = [1, 2, 3, 4, 5];
    d.cups[i].notes = 'Blind notes ${String.fromCharCode(65 + i)}';
  }
  d.cups.last.scores[4] = null;
  await r.saveCuppingDraft(row.id, d);
  await $.pumpAndSettle();
  await $.tap(find.text('Patrol blind'));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-view')));
  expect(
    $.tester
        .widget<FilledButton>(find.byKey(const ValueKey('cupping-identify')))
        .onPressed,
    null,
  );
  await $.tap(find.byKey(const ValueKey('cupping-view')));
  expect(find.textContaining('Blind Kenya'), findsNothing);
  expect(find.byKey(const ValueKey('cupping-matrix-notes-0')), findsOneWidget);
  await $.takeNativeScreenshot('blind-cupping-matrix');
  await $.tap(find.byKey(const ValueKey('cupping-view')));
  await $.tap(find.byKey(const ValueKey('cupping-tab-1')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('cupping-score-1-4-null')),
    view: find.descendant(
      of: find.byType(CuppingScores),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    ),
  );
  await $.tap(find.byKey(const ValueKey('cupping-score-1-4-null')));
  await $.tap(find.text('5').last);
  await $.tap(find.byKey(const ValueKey('cupping-score-1-4-5.0')));
  await $.tap(find.text('Unanswered').last);
  expect(
    $.tester
        .widget<FilledButton>(find.byKey(const ValueKey('cupping-identify')))
        .onPressed,
    null,
  );
  await $.tap(find.byKey(const ValueKey('cupping-score-1-4-null')));
  await $.tap(find.text('Not evaluated').last);
  await $.tap(find.byKey(const ValueKey('cupping-identify')));
  await $.tap(find.text('Cancel').last);
  expect(find.byKey(const ValueKey('cupping-coffee-0')), findsNothing);
  await $.tap(find.byKey(const ValueKey('cupping-identify')));
  await $.tap(find.byKey(const ValueKey('cupping-confirm-reveal')));
  await $.waitUntilVisible(
    find.byKey(const ValueKey('cupping-identification')),
  );
  expect(
    find.byKey(const ValueKey('cupping-identification-notes-0')),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('blind-cupping-identification');
  for (var i = 0; i < 2; i++) {
    final field = find.byKey(ValueKey('cupping-coffee-$i'));
    await $.scrollUntilVisible(finder: field);
    await $.tap(field);
    await $.tap(find.text('Blind Kenya').last);
    if (i == 0) {
      expect(
        $.tester
            .widget<FilledButton>(find.byKey(const ValueKey('cupping-finish')))
            .onPressed,
        null,
      );
      await $.platformAutomator.android.pressBack();
      await $.tap(find.text('Patrol blind'));
      await $.waitUntilVisible(
        find.byKey(const ValueKey('cupping-identification')),
      );
      final restored = CuppingDraft.fromJson(
        (await r.cuppingSession(row.id))!.draftJson,
      );
      expect(restored.cups.first.coffeeId, coffee);
      expect(restored.cups.last.coffeeId, null);
    }
  }
  final source = find.byKey(const ValueKey('cupping-source-1'));
  await $.scrollUntilVisible(finder: source);
  await $.tap(source);
  await $.tap(find.textContaining('Frozen').last);
  await $.tap(find.byKey(const ValueKey('cupping-review-scores')));
  for (final w in $.tester.widgetList<DropdownButtonFormField<double>>(
    find.byType(DropdownButtonFormField<double>),
  )) {
    expect(w.onChanged, null);
  }
  await $.takeNativeScreenshot('blind-cupping-fixed-ratings');
  await $.tap(find.byKey(const ValueKey('cupping-review-scores')));
  await $.tap(find.byKey(const ValueKey('cupping-finish')));
  await $.waitUntilVisible(find.text('Cupping saved'));
  final links = await r.cuppingCups(row.id);
  expect(links, hasLength(2));
  expect((await r.brew(links.first.brewId))!.rating, 0);
  expect((await r.brew(links.last.brewId))!.notes, 'Blind notes B');
  expect((await r.brew(links.last.brewId))!.aftertaste, null);
  expect((await r.coffeeLot(lot))!.remainingGrams, 39);
  expect((await r.frozenPortionsForLot(lot)).single.remainingGrams, 39);
  expect((await r.frozenPortionsForLot(lot)).single.id, portion);
  await $.tap(find.byKey(const ValueKey('cupping-share')));
  await $.waitUntilVisible(find.byKey(const ValueKey('cupping-share-card')));
  expect(find.text('Blind cupping'), findsOneWidget);
  await $.takeNativeScreenshot('blind-cupping-share');
  await $.tap(find.text('Cancel').last);
  expect(await r.allBrews(), hasLength(2));
}
