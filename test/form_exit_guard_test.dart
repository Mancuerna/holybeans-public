import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';

void main() {
  for (final language in ['es', 'en']) {
    for (final exit in ['cancel', 'back', 'barrier', 'drag']) {
      testWidgets(
        'coffee draft survives $exit until discard is confirmed ($language)',
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
          await tester.tap(
            find.text(language == 'es' ? 'Añadir grano' : 'Add bean'),
          );
          await tester.pumpAndSettle();
          final name = find.widgetWithText(
            TextFormField,
            language == 'es' ? 'Nombre del café' : 'Coffee name',
          );
          await tester.enterText(name, 'Keep this draft');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          switch (exit) {
            case 'cancel':
              await tester.tap(
                find.text(language == 'es' ? 'Cancelar' : 'Cancel'),
              );
            case 'back':
              await tester.binding.handlePopRoute();
            case 'barrier':
              await tester.tapAt(const Offset(5, 5));
            case 'drag':
              final rect = tester.getRect(find.byType(BottomSheet));
              await tester.dragFrom(
                Offset(rect.center.dx, rect.top + 12),
                const Offset(0, 700),
              );
          }
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('keep-editing')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('keep-editing')));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(name).controller!.text,
            'Keep this draft',
          );
          expect(find.byType(CoffeeForm), findsOneWidget);
          await tester.tap(find.text(language == 'es' ? 'Cancelar' : 'Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('discard-changes')));
          await tester.pumpAndSettle();
          expect(find.byType(CoffeeForm), findsNothing);
          expect(await db.select(db.coffees).get(), isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'unchanged and reverted forms close freely; Save bypasses discard',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
      });
      await tester.pumpWidget(
        HolyBeansApp(database: db, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      Future<void> open() async {
        await tester.tap(find.text('Add bean'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CoffeeForm), findsNothing);
      await open();
      final name = find.widgetWithText(TextFormField, 'Coffee name');
      await tester.enterText(name, 'Changed');
      await tester.enterText(name, '');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CoffeeForm), findsNothing);
      await open();
      await tester.enterText(name, 'Saved');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CoffeeForm), findsNothing);
      expect((await db.select(db.coffees).get()).single.name, 'Saved');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
