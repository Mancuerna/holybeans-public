import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'swiping a bean right brews with it, left archives and restores',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Swiped bean',
        roaster: 'R',
        initialGrams: 250,
      );
      await repository.createMethod(name: 'V60');

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      final card = find.byKey(ValueKey('bean-card-$coffee'));

      // Right: the brew form opens with the bean chosen; the card stays.
      await tester.drag(card, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.byType(BrewForm), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BrewForm),
          matching: find.text('Swiped bean'),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);

      // Left: archiving asks first, then the bean moves to Archived.
      await tester.drag(card, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await database.select(database.coffees).getSingle()).archivedAtMs,
        isNotNull,
      );

      // On Archived, left brings it back.
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(ValueKey('bean-card-$coffee')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(
        (await database.select(database.coffees).getSingle()).archivedAtMs,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
