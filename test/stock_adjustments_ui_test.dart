import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/beans/stock_adjustment_section.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);
  testWidgets('a gift from the freezer leaves unfrozen coffee untouched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(
      name: 'Congelado',
      roaster: 'R',
      initialGrams: 100,
    );
    final lot = (await repo.coffeeLots(id)).single.id;
    final portion = await repo.freezeCoffee(
      lotId: lot,
      grams: 25,
      frozenDate: '2026-10-01',
    );
    final portions = await repo.frozenPortionsForLot(lot);
    final stock = CoffeeStock(
      lots: await repo.coffeeLots(id),
      portions: portions,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: StockAdjustmentSection(
            repository: repo,
            coffee: (await repo.coffee(id))!,
            stock: stock,
            adjustments: const [],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('adjust-stock')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('adjustment-source')));
    await tester.tap(find.byKey(const ValueKey('adjustment-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(portions.single.label).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('adjustment-grams')));
    await tester.enterText(
      find.byKey(const ValueKey('adjustment-grams')),
      '10',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-adjustment')));
    await tester.tap(find.byKey(const ValueKey('save-adjustment')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => repo.coffeeStockBalance(id)), 75);
    final saved = await tester.runAsync(() => repo.frozenPortionsForLot(lot));
    expect(saved!.single.id, portion);
    expect(saved.single.remainingGrams, 15);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
  for (final s in [AppLocalizationsEs(), AppLocalizationsEn()]) {
    testWidgets(
      'adjustments validate, save decimals, cancel undo and reverse ${s.localeName}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.forTesting(NativeDatabase.memory());

        final repo = JournalRepository(db);
        final id = await repo.createCoffee(
          name: 'Test',
          roaster: 'R',
          initialGrams: 100,
        );
        final coffee = (await repo.coffee(id))!;
        final lots = await repo.coffeeLots(id);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(s.localeName),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StreamBuilder<List<StockAdjustment>>(
                  stream: repo.watchStockAdjustments(),
                  builder: (context, snapshot) => StockAdjustmentSection(
                    repository: repo,
                    coffee: coffee,
                    stock: CoffeeStock(lots: lots, portions: []),
                    adjustments: snapshot.data ?? [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('adjust-stock')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('adjustment-grams')),
          '101',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('save-adjustment')),
        );
        await tester.tap(find.byKey(const ValueKey('save-adjustment')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text(s.stockAdjustInsufficient), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('adjustment-grams')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('adjustment-grams')),
          '12,5',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('save-adjustment')),
        );
        await tester.tap(find.byKey(const ValueKey('save-adjustment')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(await tester.runAsync(() => repo.coffeeStockBalance(id)), 87.5);
        await tester.tap(
          find.byKey(const ValueKey('stock-adjustment-history')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.undo));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.cancel));
        await tester.pumpAndSettle();
        expect(await tester.runAsync(() => repo.coffeeStockBalance(id)), 87.5);
        await tester.tap(find.text(s.undo));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, s.undo));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(await tester.runAsync(() => repo.coffeeStockBalance(id)), 100);
        expect(find.text(s.stockAdjustReversed), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
        await db.close();
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
      },
    );
  }
}
