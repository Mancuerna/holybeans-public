import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/escaped_bean_card.dart';

Future<void> checkBeanPaste(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final previous = await Clipboard.getData(Clipboard.kTextPlain);
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await Clipboard.setData(const ClipboardData(text: escapedBeanCard));
    await $.tap(find.byKey(const ValueKey('bean-add-options')));
    await $.tap(find.byKey(const ValueKey('import-paste')));
    await $.waitUntilVisible(find.byKey(const ValueKey('paste-text')));
    expect(
      $.tester
          .widget<TextField>(find.byKey(const ValueKey('paste-text')))
          .controller!
          .text,
      escapedBeanCard,
    );
    await $.takeNativeScreenshot('escaped-card-clipboard');
    final field = find.byKey(const ValueKey('paste-text'));
    await $.tester.enterText(field, '{"name":');
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('paste-import')));
    expect(find.byKey(const ValueKey('paste-dialog')), findsOneWidget);
    expect($.tester.widget<TextField>(field).controller!.text, '{"name":');
    expect($.tester.widget<TextField>(field).decoration!.errorText, isNotNull);
    await $.takeNativeScreenshot('bean-paste-error-retained');
    await $.tester.enterText(
      field,
      '{"name":"Review invalid fields","roaster":"R","price":"12 euros + 3 shipping","roastDate":"2026-02-30"}',
    );
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('paste-import')));
    expect(find.byKey(const ValueKey('import-dropped')), findsOneWidget);
    await $.waitUntilVisible(
      find.byKey(const ValueKey('import-dropped-review')),
    );
    expect(await database.select(database.coffees).get(), isEmpty);
    await $.takeNativeScreenshot('bean-paste-dropped-fields');
    await $.tap(find.byKey(const ValueKey('import-dropped-review')));
    await $.tap(find.text('Cancel').last);
    await $.pumpAndSettle();
    expect(await database.select(database.coffees).get(), isEmpty);
    await $.tap(find.byKey(const ValueKey('bean-add-options')));
    await $.tap(find.byKey(const ValueKey('import-paste')));
    await $.waitUntilVisible(field);
    await $.tester.enterText(field, escapedBeanCard);
    await $.pumpAndSettle();

    await $.tap(find.byKey(const ValueKey('paste-import')));
    await $.waitUntilVisible(find.text('Hugo Pareja [SL9]'));
    await $.takeNativeScreenshot('escaped-card-preview');
    await $.tap(find.text('Save').last);
    await $.waitUntilVisible(find.text('Bean saved'));
    await $.pumpAndSettle();
    final coffee = await database.select(database.coffees).getSingle();
    expect(coffee.name, 'Hugo Pareja [SL9]');
    expect(coffee.roaster, 'Rozali Coffee');
    expect(coffee.paidPriceCents, 2500);
    final origin = await database.select(database.coffeeComponents).getSingle();
    expect(origin.altitudeMeters, 2205);
    final lot = await database.select(database.coffeeLots).getSingle();
    expect(lot.initialGrams, 100);
  } finally {
    await Clipboard.setData(previous ?? const ClipboardData(text: ''));
  }
}
