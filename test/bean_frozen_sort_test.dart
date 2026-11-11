import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';

import 'helpers/test_database.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'frozen dates, direction and independent order survive reopen ($language)',
      (tester) async {
        final database = memoryDatabase();
        addTearDown(database.close);
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = JournalRepository(database);
        final settings = ListOptionsSettings(database);
        await settings.save(
          const ListOptions(
            beanSort: BeanSort.freshness,
            beansAscending: false,
            beansCompact: true,
          ),
        );
        final ids = <String>[];
        for (final (name, dates) in [
          ('A newer', ['2026-09-01', '2026-10-20']),
          ('B older', ['2026-10-10', '2026-10-25']),
        ]) {
          final id = await repository.createCoffee(
            name: name,
            roaster: 'R',
            initialGrams: 250,
          );
          ids.add(id);
          final lot = (await repository.coffeeLots(id)).single;
          for (final date in dates) {
            final portion = await repository.freezeCoffee(
              lotId: lot.id,
              grams: 50,
              frozenDate: date,
            );
            if (date == '2026-09-01') await repository.thawCoffee(portion, 50);
          }
        }
        final dates = oldestFrozenDatesByCoffee(
          await database.select(database.coffeeLots).get(),
          await database.select(database.frozenPortions).get(),
        );
        expect(dates[ids[0]], DateTime(2026, 10, 20));
        expect(dates[ids[1]], DateTime(2026, 10, 10));
        Future<void> tab(int index) async {
          final target = find
              .descendant(
                of: find.byKey(const ValueKey('bean-tabs')),
                matching: find.byType(Tab),
              )
              .at(index);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Future<void> open() async {
          await tester.pumpWidget(
            HolyBeansApp(database: database, initialLocale: Locale(language)),
          );
          await tester.pumpAndSettle();
          final nav = tester.getRect(find.byType(NavigationBar));
          await tester.tapAt(
            Offset(nav.left + nav.width * 1.5 / 4, nav.center.dy),
          );
          await tester.pumpAndSettle();
          await tab(1);
        }

        Future<void> menu() async {
          await tester.tap(find.byKey(const ValueKey('bean-sort')));
          await tester.pumpAndSettle();
        }

        List<String> names() => tester
            .widgetList<BeanCard>(find.byType(BeanCard))
            .map((card) => card.coffee.name)
            .toList();
        final frozenLabel = language == 'es'
            ? 'Fecha de congelación'
            : 'Freeze date';
        final freshnessLabel = language == 'es'
            ? 'Frescura (gastar antes)'
            : 'Freshness (use soon)';
        await open();
        expect(names(), ['B older', 'A newer']);
        await menu();
        expect(
          find.widgetWithText(CheckedPopupMenuItem<int>, freshnessLabel),
          findsNothing,
        );
        expect(
          tester
              .widget<CheckedPopupMenuItem<int>>(
                find.widgetWithText(CheckedPopupMenuItem<int>, frozenLabel),
              )
              .checked,
          isTrue,
        );
        await tester.tap(
          find.widgetWithText(
            CheckedPopupMenuItem<int>,
            language == 'es' ? 'Descendente' : 'Descending',
          ),
        );
        await tester.pumpAndSettle();
        expect(names(), ['A newer', 'B older']);
        await tab(0);
        await menu();
        expect(
          find.widgetWithText(CheckedPopupMenuItem<int>, frozenLabel),
          findsNothing,
        );
        expect(
          tester
              .widget<CheckedPopupMenuItem<int>>(
                find.widgetWithText(CheckedPopupMenuItem<int>, freshnessLabel),
              )
              .checked,
          isTrue,
        );
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<int>, freshnessLabel),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await open();
        expect(names(), ['A newer', 'B older']);
        expect((await settings.load()).frozenBeansAscending, isFalse);
        expect((await settings.load()).beanSort, BeanSort.freshness);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
