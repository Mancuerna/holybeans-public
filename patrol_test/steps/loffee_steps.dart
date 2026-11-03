import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/loffee_key_store.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/fake_loffee.dart';
import '../support/smoke_support.dart';

/// Real Android credential storage and UI, with a synthetic catalog only.
Future<void> checkLoffeeImport(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  const keys = AndroidLoffeeKeyStore();
  final before = await keys.read();
  final api = FakeLoffeeApi()
    ..beans = [
      LoffeeBean.fromJson({
        ...loffeeFixture,
        'degree': 'Nordic Light To Light',
      }),
    ];
  final incoming = IncomingShares();
  try {
    await keys.delete();
    expect(await keys.read(), isNull);
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        database: database,
        initialLocale: const Locale('en'),
        loffee: LoffeeServices(api: api, keys: keys),
        incoming: incoming,
      ),
    );
    await $.tap(find.byKey(const ValueKey('bean-add-manual')));
    await $.waitUntilVisible(find.byType(CoffeeForm));
    await $.tap(find.text('Cancel').last);
    await $.tester.longPress(find.byKey(const ValueKey('bean-add-manual')));
    await $.pumpAndSettle();
    await $.waitUntilVisible(find.byKey(const ValueKey('import-loffee')));
    expect(find.byKey(const ValueKey('bean-add-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-scan')), findsOneWidget);
    await $.takeNativeScreenshot('bean-add-speed-dial');
    await $.platformAutomator.android.pressBack();
    await $.waitUntilVisible(find.byKey(const ValueKey('bean-add-options')));
    await $.tap(find.byKey(const ValueKey('bean-add-options')));
    await $.tap(find.byKey(const ValueKey('import-loffee')));
    await $.waitUntilVisible(find.byKey(const ValueKey('loffee-add-key')));
    await $.tap(find.byKey(const ValueKey('loffee-add-key')));
    await $.waitUntilVisible(find.byKey(const ValueKey('loffee-key-input')));
    await $.enterText(
      find.byKey(const ValueKey('loffee-key-input')),
      'patrol-test-only-key',
    );
    await $.tap(find.byKey(const ValueKey('loffee-key-save')));
    expect(await keys.read(), 'patrol-test-only-key');
    await $.enterText(find.byKey(const ValueKey('loffee-query')), 'Gesha');
    await $.tap(find.byKey(const ValueKey('loffee-search')));
    await $.waitUntilVisible(find.byKey(const ValueKey('loffee-select-42')));
    await $.takeNativeScreenshot('loffee-catalog-results');
    await $.tap(find.byKey(const ValueKey('loffee-select-42')));
    await $.waitUntilVisible(find.byType(CoffeeForm));
    expect(
      find.text('Approximate roast from Loffee: Nordic Light To Light'),
      findsOneWidget,
    );
    await $.takeNativeScreenshot('loffee-approximate-roast-review');
    final altitude = find.byKey(const ValueKey('coffee-origin-altitude-0'));
    await $.scrollUntilVisible(finder: altitude);
    expect($.tester.widget<TextFormField>(altitude).controller!.text, '1200');
    final upper = find.byKey(const ValueKey('coffee-origin-altitude-max-0'));
    expect($.tester.widget<TextFormField>(upper).controller!.text, '1600');
    await $.enterText(upper, '1100');
    await $.tap(find.text('Save').last);
    await $.scrollUntilVisible(
      finder: find.text(
        'Enter a starting altitude and an end value at least as high.',
      ),
    );
    expect(await database.select(database.coffees).get(), isEmpty);
    await $.takeNativeScreenshot('loffee-altitude-range-validation');

    expect(await database.select(database.coffees).get(), isEmpty);
    await $.tap(find.text('Cancel').last);
    await $.tap(find.byKey(const ValueKey('discard-changes')));
    expect(await database.select(database.coffees).get(), isEmpty);

    await $.tap(find.byKey(const ValueKey('bean-add-options')));
    await $.tap(find.byKey(const ValueKey('import-loffee')));
    await $.enterText(find.byKey(const ValueKey('loffee-query')), 'Gesha');
    await $.tap(find.byKey(const ValueKey('loffee-search')));
    await $.tap(find.byKey(const ValueKey('loffee-select-42')));
    await $.scrollUntilVisible(finder: altitude);
    await $.takeNativeScreenshot('loffee-altitude-range-review');
    final flavorInput = find.byKey(const ValueKey('coffee-flavor-profile'));
    await $.scrollUntilVisible(
      finder: flavorInput,
      view: verticalScrollable(find.byType(CoffeeForm)),
    );
    expect(find.widgetWithText(InputChip, 'jasmine'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'peach'), findsOneWidget);
    await $.takeNativeScreenshot('loffee-flavor-note-chips');
    await $.tap(find.text('Save').last);
    await $.waitUntilVisible(find.text('Bean saved'));
    final coffee = await database.select(database.coffees).getSingle();
    expect(coffee.roastLevel, 'light');
    expect(coffee.flavorProfile, 'Jasmine, peach');
    expect(coffee.paidPriceCents, isNull);
    expect(coffee.archivedAtMs, isNull);
    expect(coffee.notes, isNot(contains('1200–1600 m')));
    final origin = await database.select(database.coffeeComponents).getSingle();
    expect((origin.altitudeMeters, origin.altitudeMaxMeters), (1200, 1600));
    expect(coffee.notes, isNot(contains('Nordic Light To Light')));
    expect(coffee.notes, isNot(contains('Roast level:')));
    expect(
      (await database.select(database.coffeeComponents).get()).single.country,
      'Spain',
    );
    expect(
      (await database.select(database.appPreferences).get()).every(
        (row) => !row.toString().contains('patrol-test-only-key'),
      ),
      isTrue,
    );
    for (final lot in await database.select(database.coffeeLots).get()) {
      expect(lot.roastDate, isNull);
      expect(lot.initialGrams, isNull);
    }
    await $.tap(find.byKey(const ValueKey('settings-button')));
    final setting = find.byKey(const ValueKey('loffee-key-settings'));
    await $.scrollUntilVisible(finder: setting);
    await $.tap(setting);
    await $.waitUntilVisible(find.byKey(const ValueKey('loffee-key-delete')));
    await $.tap(find.byKey(const ValueKey('loffee-key-delete')));
    expect(await keys.read(), isNull);
  } finally {
    incoming.dispose();
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    if (before == null) {
      await keys.delete();
    } else {
      await keys.save(before);
    }
  }
}
