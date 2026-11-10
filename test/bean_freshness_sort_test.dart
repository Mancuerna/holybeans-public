import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';

import 'helpers/test_database.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'freshness order, direction and favorites survive reopen ($language)',
      (tester) async {
        final database = memoryDatabase();
        addTearDown(database.close);
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = JournalRepository(database);
        await ListOptionsSettings(database)
            .save(const ListOptions(beansCompact: true));
        final window = freshnessWindow(
          roastLevel: 'medium',
          style: BrewStyle.filter,
        );
        final now = DateTime.now();
        final ids = <String, String>{};
        for (final (name, day) in [
          ('A resting', 1),
          ('B prime', window.primeStart),
          ('C good', window.primeEnd + 1),
          ('D aging', window.goodUntil + 1),
          ('E stale', window.agingUntil + 1),
          ('F unknown', null),
        ]) {
          ids[name] = await repository.createCoffee(
            name: name,
            roaster: 'Roaster',
            roastLevel: 'medium',
            roastDate: day == null
                ? null
                : DateTime(
                    now.year,
                    now.month,
                    now.day - day,
                  ).toIso8601String().substring(0, 10),
            initialGrams: 250,
          );
        }
        Future<void> openApp() async {
          await tester.pumpWidget(
            HolyBeansApp(database: database, initialLocale: Locale(language)),
          );
          await tester.pumpAndSettle();
          final nav = tester.getRect(find.byType(NavigationBar));
          await tester.tapAt(
            Offset(nav.left + nav.width * 1.5 / 4, nav.center.dy),
          );
          await tester.pumpAndSettle();
        }

        Future<void> choose(String label) async {
          await tester.tap(find.byKey(const ValueKey('bean-sort')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(CheckedPopupMenuItem<int>, label),
          );
          await tester.pumpAndSettle();
        }

        List<String> names() => tester
            .widgetList<BeanCard>(find.byType(BeanCard))
            .map((card) => card.coffee.name)
            .toList();
        final natural = ids.keys.toList();
        final urgent = [...natural.take(5).toList().reversed, natural.last];
        await openApp();
        await choose(
          language == 'es' ? 'Frescura (gastar antes)' : 'Freshness (use soon)',
        );
        expect(names(), urgent);
        final settings = ListOptionsSettings(database);
        expect((await settings.load()).beanSort, BeanSort.freshness);
        expect((await settings.load()).beansAscending, isFalse);
        await choose(language == 'es' ? 'Ascendente' : 'Ascending');
        expect(names(), natural);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await openApp();
        expect(names(), natural);
        expect((await settings.load()).beanSort, BeanSort.freshness);
        await choose(language == 'es' ? 'Descendente' : 'Descending');
        await repository.setCoffeeFavorite(ids['A resting']!, favorite: true);
        await tester.pumpAndSettle();
        expect(names(), [
          'A resting',
          ...urgent.where((name) => name != 'A resting'),
        ]);
        await tester.tap(find.byKey(const ValueKey('bean-sort')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bean-favorites-first')));
        await tester.pumpAndSettle();
        expect(names(), urgent);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  test('freshness options survive backup and restore with independent archived order', () async {
    final source = memoryDatabase();
    final target = memoryDatabase();
    addTearDown(source.close);
    addTearDown(target.close);
    const options = ListOptions(
      frozenBeansAscending: false,
      beansByRoaster: true,
      beanSort: BeanSort.freshness,
      beansAscending: false,
      archivedBeanSort: BeanSort.roastDate,
      archivedBeansAscending: true,
    );
    await ListOptionsSettings(source).save(options);
    await JournalBackup(target)
        .restoreJson(await JournalBackup(source).exportJson());
    expect(
      (await ListOptionsSettings(target).load()).toJson(),
      options.toJson(),
    );
  });
}
