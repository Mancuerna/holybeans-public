import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/frozen_stock_badge.dart';

void main() {
  test(
    'all frozen requires known available stock and a remaining frozen portion',
    () {
      expect(frozenStockState(0, 10), FrozenStockState.all);
      expect(frozenStockState(20, 10), FrozenStockState.some);
      expect(frozenStockState(null, 10), FrozenStockState.some);
      expect(frozenStockState(0, 0), FrozenStockState.none);
      expect(frozenStockState(20, 0), FrozenStockState.none);
    },
  );
  for (final lang in ['es', 'en']) {
    testWidgets('coffee picker shows partial and all frozen at 320px ($lang)', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = JournalRepository(db);
      for (final name in [
        'Partial coffee with a very long name',
        'All frozen coffee',
        'Fresh coffee',
      ]) {
        await repo.createCoffee(name: name, roaster: 'R', initialGrams: 100);
      }
      final coffees = await db.select(db.coffees).get();
      final lots = await db.select(db.coffeeLots).get();
      final partial = coffees.firstWhere((c) => c.name.startsWith('Partial'));
      final all = coffees.firstWhere((c) => c.name.startsWith('All'));
      final fresh = coffees.firstWhere((c) => c.name.startsWith('Fresh'));
      await repo.freezeCoffee(
        lotId: lots.firstWhere((l) => l.coffeeId == partial.id).id,
        grams: 30,
        frozenDate: '2026-10-11',
      );
      await repo.freezeCoffee(
        lotId: lots.firstWhere((l) => l.coffeeId == all.id).id,
        grams: 100,
        frozenDate: '2026-10-11',
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CoffeePicker(
                repository: repo,
                coffees: coffees,
                value: fresh.id,
                onChanged: (id) => selected = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brew-coffee-picker')));
      await tester.pumpAndSettle();
      expect(
        find
            .byTooltip(
              lang == 'es'
                  ? 'Tiene porciones congeladas'
                  : 'Has frozen portions',
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .byTooltip(
              lang == 'es'
                  ? 'Todo el café disponible está congelado'
                  : 'All remaining coffee is frozen',
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text(all.name).last);
      await tester.pumpAndSettle();
      expect(selected, all.id);
      expect(tester.takeException(), isNull);
      expect((await repo.coffeeLots(all.id)).single.remainingGrams, 0);
      expect(
        (await repo.frozenPortionsForLot(
          lots.firstWhere((l) => l.coffeeId == all.id).id,
        )).single.remainingGrams,
        100,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
