import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/beans/freezer_widgets.dart';
import 'package:holybeans/ui/brews/brew_frozen_picker.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final remainder in [true, false]) {
    testWidgets(
      'freeze division preview and saved inventory, remainder $remainder',
      (tester) async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final id = await repo.createCoffee(
          name: 'Bulk',
          roaster: 'R',
          initialGrams: 950,
        );
        final lots = await repo.coffeeLots(id);
        await tester.pumpWidget(
          localizedApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showFreezeSheet(context, repo.freezer, lots: lots),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('freeze-grams')),
          '950',
        );
        await tester.tap(find.byKey(const ValueKey('freeze-split')));
        await tester.pumpAndSettle();
        expect(find.text('Create 9 portions of 100 g.'), findsOneWidget);
        if (!remainder) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('freeze-remainder')),
          );
          await tester.tap(find.byKey(const ValueKey('freeze-remainder')));
          await tester.pumpAndSettle();
        }
        final save = find.byKey(const ValueKey('freeze-save'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          save,
          200,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final action = tester.widget<FilledButton>(save).onPressed!;
        action();
        action();
        await tester.pumpAndSettle();
        expect(
          (await repo.frozenPortionsForLot(lots.single.id)).length,
          remainder ? 10 : 9,
        );
        expect(
          (await repo.coffeeLot(lots.single.id))!.remainingGrams,
          remainder ? 0 : 50,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'frozen picker cancels without choosing and identifies the portion',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(
        name: 'Bean',
        roaster: 'R',
        initialGrams: 900,
      );
      final lot = (await repo.coffeeLots(coffee)).single.id;
      await repo.freezeCoffeePortions(
        lotId: lot,
        amounts: [100, 800],
        frozenDate: '2026-10-19',
      );
      final portions = await repo.frozenPortionsForLot(lot);
      FrozenPortion? chosen;
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await chooseFrozenForBrew(context, portions, 18);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('brew-frozen-${portions.last.id}')));
      await tester.pumpAndSettle();
      expect(chosen!.id, portions.last.id);
      expect((await repo.frozenPortionsForLot(lot)).last.remainingGrams, 800);
    },
  );
}
