import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'mixed imported notes survive backup and shared bean round trips',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(restored.close);
      final repo = JournalRepository(db);
      const profile = 'Peach, JASMINE, durazno, lemon cake, algo muy personal';
      final id = await repo.createCoffeeWithComponents(
        name: 'Imported',
        roaster: 'R',
        components: const [],
        flavorProfile: profile,
      );
      final coffee = (await repo.coffee(id))!;
      final card = SharedBean.fromCoffee(coffee, const [], const []);
      expect(card.flavorProfile, profile);
      await JournalBackup(restored)
          .restoreJson(await JournalBackup(db).exportJson());
      expect(
        (await restored.select(restored.coffees).getSingle()).flavorProfile,
        profile,
      );
      expect((await repo.coffee(id))!.flavorProfile, profile);
    },
  );

  for (final language in ['es', 'en']) {
    testWidgets(
      'Save includes pending note and discard guard sees it ($language)',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await db.close();
        });
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          HolyBeansApp(database: db, initialLocale: Locale(language)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bean-add-manual')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            language == 'es' ? 'Nombre del café' : 'Coffee name',
          ),
          'Tagged coffee',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('coffee-flavor-profile'));
        final scrollable = find
            .descendant(
              of: find.byType(CoffeeForm),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(input, 250, scrollable: scrollable);
        await tester.enterText(input, 'Peach, Jazmín, lemon cake');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'es' ? 'Cancelar' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('keep-editing')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('keep-editing')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(input).controller!.text,
          ' lemon cake',
        );
        await tester.tap(find.text(language == 'es' ? 'Guardar' : 'Save'));
        await tester.pumpAndSettle();
        final coffee = await db.select(db.coffees).getSingle();
        expect(
          coffee.flavorProfile,
          language == 'es'
              ? 'melocotón, jazmín, lemon cake'
              : 'peach, jasmine, lemon cake',
        );
        expect(find.byType(CoffeeForm), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
