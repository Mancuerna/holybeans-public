import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  Future<void> openBeans(WidgetTester tester) async {
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Beans'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDeletion(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('bean-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete coffee'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unused coffee deletion can be cancelled and confirmed from the card menu',
    (tester) async {
      final id = await repository.createCoffee(
        name: 'Mistake',
        roaster: 'Test',
        initialGrams: 250,
      );
      await openBeans(tester);
      await openDeletion(tester, id);
      expect(find.textContaining('Mistake'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await repository.coffee(id), isNotNull);
      await openDeletion(tester, id);
      await tester.tap(find.byKey(const ValueKey('delete-bean-confirm')));
      await tester.pumpAndSettle();
      expect(await repository.coffee(id), isNull);
      expect(find.byKey(ValueKey('bean-card-$id')), findsNothing);
      expect(find.text('Coffee deleted'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('active and archived brews both hide deletion', (tester) async {
    final ids = <String>[];
    for (final archived in [false, true]) {
      final id = await repository.createCoffee(
        name: archived ? 'Archived brew' : 'Active brew',
        roaster: 'Test',
      );
      ids.add(id);
      final brew = await repository.createBrew(coffeeId: id, methodName: 'V60');
      if (archived) {
        await (database.update(database.brews)
              ..where((row) => row.id.equals(brew)))
            .write(const BrewsCompanion(archivedAtMs: Value(1)));
      }
    }
    await openBeans(tester);
    for (final id in ids) {
      await tester.tap(find.byKey(ValueKey('bean-menu-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Delete coffee'), findsNothing);
      expect(find.text('Edit bean'), findsOneWidget);
      Navigator.of(tester.element(find.text('Edit bean'))).pop();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a brew added while confirmation is open prevents deletion', (
    tester,
  ) async {
    final id = await repository.createCoffee(
      name: 'Race',
      roaster: 'Test',
      initialGrams: 250,
    );
    await openBeans(tester);
    await openDeletion(tester, id);
    await repository.createBrew(coffeeId: id, methodName: 'V60');
    await tester.tap(find.byKey(const ValueKey('delete-bean-confirm')));
    await tester.pumpAndSettle();
    expect(await repository.coffee(id), isNotNull);
    expect(
      find.text('This coffee has brews and cannot be deleted.'),
      findsOneWidget,
    );
    expect(await repository.allBrews(), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
