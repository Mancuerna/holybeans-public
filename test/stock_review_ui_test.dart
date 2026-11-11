import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_mutations.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/stock_review_card.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final s in [AppLocalizationsEs(), AppLocalizationsEn()]) {
    testWidgets(
      'legacy review requires confirmation and cancels cleanly ${s.localeName}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final coffee = await repo.createCoffee(
          name: 'Test',
          roaster: 'R',
          initialGrams: 100,
        );
        final lot = (await repo.coffeeLots(coffee)).single.id;
        final id = await repo.createBrew(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 18,
        );
        await (db.update(db.brews)..where((b) => b.id.equals(id))).write(
          const BrewsCompanion(
            stockReviewPending: Value(true),
            archivedAtMs: Value(1),
          ),
        );
        Brew? resolved;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(s.localeName),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StockReviewCard(
                  repository: JournalMutations(repo),
                  brew: (await repo.brew(id))!,
                  onResolved: (b) => resolved = b,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('stock-review-deduct')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.cancel));
        await tester.pumpAndSettle();
        expect(resolved, isNull);
        expect((await repo.coffeeLot(lot))!.remainingGrams, 82);
        await tester.tap(find.byKey(const ValueKey('stock-review-keep')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.stockReviewConfirm));
        await tester.pumpAndSettle();
        expect(resolved?.stockReviewPending, false);
        expect((await repo.coffeeLot(lot))!.remainingGrams, 82);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
