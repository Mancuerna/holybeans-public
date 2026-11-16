import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'accessories can be searched, combined and cleared independently',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(
        name: 'Coffee',
        roaster: 'Roaster',
      );
      final v60 = await repo.createMethod(name: 'V60');
      final espresso = await repo.createMethod(name: 'Espresso');
      final paper = await repo.createTool(
        name: 'Papel Cafec abacá',
        methodIds: [v60, espresso],
      );
      final basket = await repo.createTool(
        name: 'Cesta de 58 mm',
        methodIds: [espresso],
      );
      for (final (method, name, tools) in [
        (v60, 'V60', [paper]),
        (espresso, 'Espresso', [basket]),
        (espresso, 'Espresso', [paper, basket]),
      ]) {
        await repo.createBrew(
          coffeeId: coffee,
          methodId: method,
          methodName: name,
          methodToolIds: tools,
        );
      }
      await repo.setMethodToolArchived(paper, archived: true);
      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: db),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 2);
      expect(find.byType(Card), findsNWidgets(3));

      Future<void> openFilters() async {
        await tester.tap(find.byKey(const ValueKey('history-filter-button')));
        await tester.pumpAndSettle();
      }

      Future<void> openAccessories() async {
        final field = find.byKey(const ValueKey('history-tool-filter'));
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
      }

      Future<void> closeSheet() async {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      Future<void> choose(String id) async {
        await tester.tap(find.byKey(ValueKey('history-tool-choice-$id')));
        await tester.pumpAndSettle();
      }

      await openFilters();
      expect(find.text('Any method'), findsOneWidget);
      await openAccessories();
      final search = find.byKey(const ValueKey('history-tool-search'));
      await tester.enterText(search, 'abaca');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('history-tool-choice-$paper')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('history-tool-choice-$basket')), findsNothing);
      expect(find.text('Archived'), findsOneWidget);
      await choose(paper);
      await closeSheet();
      await closeSheet();
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byKey(const ValueKey('history-active-method')), findsNothing);

      await openFilters();
      await openAccessories();
      await choose(basket);
      await closeSheet();
      expect(find.text('2 accessories selected'), findsOneWidget);
      await closeSheet();
      expect(find.byType(Card), findsOneWidget);
      expect(
        find.byKey(ValueKey('history-active-tool-$paper')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('history-active-tool-$basket')),
        findsOneWidget,
      );

      await openFilters();
      final method = find.byKey(const ValueKey('history-method-filter'));
      await tester.ensureVisible(method);
      await tester.tap(method);
      await tester.pumpAndSettle();
      await tester.tap(find.text('V60').last);
      await tester.pumpAndSettle();
      await closeSheet();
      expect(find.byType(Card), findsNothing);
      expect(find.text('No matching brews.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear filter: V60'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      await tester.tap(find.byTooltip('Clear filter: Papel Cafec abacá'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byKey(ValueKey('history-active-tool-$paper')), findsNothing);
      expect(
        find.byKey(ValueKey('history-active-tool-$basket')),
        findsOneWidget,
      );

      await openFilters();
      await openAccessories();
      await tester.enterText(search, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching accessories.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-any-tool')));
      await tester.pumpAndSettle();
      await closeSheet();
      await closeSheet();
      expect(find.byType(Card), findsNWidgets(3));
      expect(find.byKey(ValueKey('history-active-tool-$basket')), findsNothing);

      await openFilters();
      await openAccessories();
      await choose(paper);
      await closeSheet();
      await closeSheet();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(3));
      expect(find.byKey(ValueKey('history-active-tool-$paper')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
