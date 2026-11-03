import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final locale in ['en', 'es']) {
    testWidgets(
      'altitude endpoints sit together, validate and survive editing ($locale)',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          HolyBeansApp(database: db, initialLocale: Locale(locale)),
        );
        await tester.pumpAndSettle();
        final spanish = locale == 'es';
        if (spanish) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(spanish ? 'Añadir grano' : 'Add bean'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            spanish ? 'Nombre del café' : 'Coffee name',
          ),
          'Altitude range',
        );
        final addOrigin = find.text(spanish ? 'Añadir origen' : 'Add origin');
        await tester.ensureVisible(addOrigin);
        await tester.tap(addOrigin);
        await tester.pumpAndSettle();
        final low = find.byKey(const ValueKey('coffee-origin-altitude-0'));
        final high = find.byKey(const ValueKey('coffee-origin-altitude-max-0'));
        final scrollable = find
            .descendant(
              of: find.byType(CoffeeForm),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(low, 220, scrollable: scrollable);
        expect(tester.getRect(low).left, lessThan(tester.getRect(high).left));
        expect(tester.getRect(low).top, tester.getRect(high).top);
        await tester.enterText(high, '1456');
        await tester.tap(find.text(spanish ? 'Guardar' : 'Save').last);
        await tester.pumpAndSettle();
        expect(await db.select(db.coffees).get(), isEmpty);
        final error = spanish
            ? 'Indica la altitud inicial y un valor final igual o mayor.'
            : 'Enter a starting altitude and an end value at least as high.';
        expect(find.text(error), findsOneWidget);
        await tester.enterText(low, '1500');
        await tester.tap(find.text(spanish ? 'Guardar' : 'Save').last);
        await tester.pumpAndSettle();
        expect(await db.select(db.coffees).get(), isEmpty);
        await tester.enterText(low, '1111');
        await tester.tap(find.text(spanish ? 'Guardar' : 'Save').last);
        await tester.pumpAndSettle();
        final original = await db.select(db.coffeeComponents).getSingle();
        expect(
          (original.altitudeMeters, original.altitudeMaxMeters),
          (1111, 1456),
        );
        await tapBottomDestination(tester, 1);
        await tester.pumpAndSettle();
        expect(find.textContaining('1111–1456 m'), findsWidgets);
        await tester.tap(find.text('Altitude range').first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find
              .descendant(
                of: find.byType(CoffeeDetailsSheet),
                matching: find.text('1111–1456 m'),
              )
              .first,
          220,
          scrollable: find
              .descendant(
                of: find.byType(CoffeeDetailsSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('1111–1456 m'), findsWidgets);
        await tester.ensureVisible(
          find.byTooltip(spanish ? 'Editar grano' : 'Edit bean'),
        );
        await tester.tap(
          find.byTooltip(spanish ? 'Editar grano' : 'Edit bean'),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(low, 220, scrollable: scrollable);
        expect(tester.widget<TextFormField>(low).controller!.text, '1111');
        expect(tester.widget<TextFormField>(high).controller!.text, '1456');
        await tester.enterText(high, '');
        await tester.tap(find.text(spanish ? 'Guardar' : 'Save').last);
        await tester.pumpAndSettle();
        final edited = await db.select(db.coffeeComponents).getSingle();
        expect(edited.id, original.id);
        expect(edited.altitudeMeters, 1111);
        expect(edited.altitudeMaxMeters, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
