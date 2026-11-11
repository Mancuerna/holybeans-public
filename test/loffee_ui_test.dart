import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/beans/loffee_search_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:image/image.dart' as img;

import 'helpers/fake_loffee.dart';
import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late MemoryLoffeeKeys keys;
  late FakeLoffeeApi api;
  setUp(() {
    database = memoryDatabase();
    keys = MemoryLoffeeKeys('test-only-key');
    api = FakeLoffeeApi();
  });
  tearDown(() => database.close());

  Future<void> launch(
    WidgetTester tester, {
    PhotoStore? photos,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(
          database: database,
          photos: photos,
          loffee: LoffeeServices(api: api, keys: keys),
        ),
        initialLocale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('bean-add-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-loffee')));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('loffee-query')), 'Gesha');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('loffee-search')));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('loffee-select-42'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'normal tap is manual; long press opens actions and back closes them',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const ValueKey('bean-add-manual')));
      await tester.pumpAndSettle();
      expect(find.byType(CoffeeForm), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('bean-add-manual')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bean-add-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('import-paste')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bean-add-menu')), findsNothing);
      expect(await database.select(database.coffees).get(), isEmpty);
      await finish(tester);
    },
  );
  testWidgets('a missing key can be saved securely through the first search', (
    tester,
  ) async {
    keys.value = null;
    await launch(tester);
    await openSearch(tester);
    expect(api.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('loffee-add-key')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('loffee-key-input')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const ValueKey('loffee-key-input')),
      'test-user-key',
    );
    await tester.tap(find.byKey(const ValueKey('loffee-key-save')));
    await tester.pumpAndSettle();
    expect(keys.value, 'test-user-key');
    expect(await database.select(database.appPreferences).get(), isEmpty);
    await search(tester);
    expect(api.calls.single.key, 'test-user-key');
    await finish(tester);
  });
  for (final fails in [false, true]) {
    testWidgets(
      'late catalogue response after Back is ignored (error: $fails)',
      (tester) async {
        final delayed = _DelayedLoffeeApi();
        api = delayed;
        await launch(tester);
        await openSearch(tester);
        await tester.enterText(
          find.byKey(const ValueKey('loffee-query')),
          'Gesha',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('loffee-search')));
        await tester.pump();
        Navigator.of(tester.element(find.byType(LoffeeSearchPage))).pop();
        await tester.pump(const Duration(seconds: 1));
        if (fails) {
          delayed.response.completeError(
            const LoffeeException(LoffeeFailure.network),
          );
        } else {
          delayed.response.complete(LoffeePage(delayed.beans, hasMore: false));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LoffeeSearchPage), findsNothing);
        expect(find.byType(CoffeeForm), findsNothing);
        expect(await database.select(database.coffees).get(), isEmpty);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }
  testWidgets('selection only prefills; cancel keeps the journal empty', (
    tester,
  ) async {
    await launch(tester);
    await openSearch(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await search(tester);
    await select(tester);
    expect(
      find.widgetWithText(TextFormField, 'Patrol Loffee Gesha'),
      findsOneWidget,
    );
    expect(await database.select(database.coffees).get(), isEmpty);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(await database.select(database.coffees).get(), isEmpty);
    await finish(tester);
  });
  testWidgets(
    'save keeps source details without fabricated date, price or stock',
    (tester) async {
      await launch(tester);
      await openSearch(tester);
      await search(tester);
      await select(tester);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final coffee = await database.select(database.coffees).getSingle();
      expect(coffee.roastLevel, 'light');
      expect(coffee.paidPriceCents, isNull);
      expect(coffee.archivedAtMs, isNull);
      expect(coffee.notes, isNot(contains('1200–1600 m')));
      expect(coffee.notes, contains('Omni'));
      expect(coffee.notes, contains('Data from Loffee Labs'));
      final origin = await database
          .select(database.coffeeComponents)
          .getSingle();
      expect((origin.altitudeMeters, origin.altitudeMaxMeters), (1200, 1600));
      expect(coffee.notes, isNot(contains('Roast level:')));
      final lots = await JournalRepository(database).coffeeLots(coffee.id);
      for (final lot in lots) {
        expect(lot.roastDate, isNull);
        expect(lot.initialGrams, isNull);
        expect(lot.remainingGrams, isNull);
      }
      expect(
        (await JournalRepository(database).coffeeComponents(coffee.id))
            .single
            .country,
        'Spain',
      );
      await finish(tester);
    },
  );
  for (final locale in ['en', 'es']) {
    testWidgets(
      'approximate roast is editable without adding notes ($locale)',
      (tester) async {
        api.beans = [
          LoffeeBean.fromJson({...loffeeFixture, 'degree': 'Light To Medium'}),
        ];
        await launch(tester, locale: Locale(locale));
        await openSearch(tester);
        await search(tester);
        await select(tester);
        final hint = locale == 'es'
            ? 'Tueste aproximado desde Loffee: Light To Medium'
            : 'Approximate roast from Loffee: Light To Medium';
        expect(find.text(hint), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('roast-level-omni')),
              )
              .selected,
          isTrue,
        );
        final dark = find.byKey(const ValueKey('roast-level-dark'));
        await tester.ensureVisible(dark);
        await tester.tap(dark);
        await tester.pumpAndSettle();
        expect(find.text(hint), findsNothing);
        await tester.tap(find.text(locale == 'es' ? 'Guardar' : 'Save').last);
        await tester.pumpAndSettle();
        final coffee = await database.select(database.coffees).getSingle();
        expect(coffee.roastLevel, 'dark');
        expect(coffee.notes, isNot(contains('Light To Medium')));
        expect(coffee.notes, isNot(contains('1200–1600 m')));
        await finish(tester);
      },
    );
  }
  testWidgets('an existing coffee asks before adding another', (tester) async {
    await JournalRepository(database)
        .createCoffee(name: 'Patrol Loffee Gesha', roaster: 'Test Roaster');
    await launch(tester);
    // Existing beans make Home offer Brew; enter the Beans tab.
    await tester.tap(find.text('Beans').last);
    await tester.pumpAndSettle();
    await openSearch(tester);
    await search(tester);
    await select(tester);
    expect(find.byKey(const ValueKey('import-duplicate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-add-anyway')));
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsOneWidget);
    expect(await database.select(database.coffees).get(), hasLength(1));
    await finish(tester);
  });
  testWidgets('pagination uses the submitted search, not unfinished edits', (
    tester,
  ) async {
    api.hasMore = true;
    await launch(tester);
    await openSearch(tester);
    await search(tester);
    await tester.enterText(
      find.byKey(const ValueKey('loffee-query')),
      'unfinished',
    );
    final next = find.byKey(const ValueKey('loffee-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(api.calls.last, (key: 'test-only-key', query: 'Gesha', page: 2));
    await finish(tester);
  });
  testWidgets('network error is recoverable and does not create inventory', (
    tester,
  ) async {
    api.failure = LoffeeFailure.network;
    await launch(tester);
    await openSearch(tester);
    await search(tester);
    expect(find.byKey(const ValueKey('loffee-error')), findsOneWidget);
    expect(await database.select(database.coffees).get(), isEmpty);
    api.failure = null;
    await search(tester);
    expect(find.byKey(const ValueKey('loffee-select-42')), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
    'Settings offers key replacement and removal, with imports on Beans',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();
      final setting = find.byKey(const ValueKey('loffee-key-settings'));
      await tester.scrollUntilVisible(setting, 250);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      final input = tester.widget<TextFormField>(
        find.byKey(const ValueKey('loffee-key-input')),
      );
      expect(
        input.controller!.text,
        isEmpty,
        reason: 'a saved key is never prefilled or displayed',
      );
      expect(find.byKey(const ValueKey('import-beans')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('loffee-key-delete')));
      await tester.pumpAndSettle();
      expect(keys.value, isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'small screen and large Spanish text can scroll menu and search with keyboard',
    (tester) async {
      await launch(tester, locale: const Locale('es'));
      tester.view.physicalSize = const Size(320, 600);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await openSearch(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(LoffeeSearchPage), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets('a catalog photo is discarded when the form is cancelled', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('loffee-photo-test-'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = PhotoStore(directory);
    api.beans = [
      LoffeeBean.fromJson({
        ...loffeeFixture,
        'image': 'https://image.example/bag.jpg',
      }),
    ];
    api.image = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 2, height: 2)),
    );
    await launch(tester, photos: store);
    await openSearch(tester);
    await search(tester);
    await select(tester);
    final photo = find.byKey(const ValueKey('loffee-import-photo'));
    await tester.scrollUntilVisible(
      photo,
      250,
      scrollable: find
          .descendant(
            of: find.byType(CoffeeForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(photo);
    await tester.runAsync(() async {
      await tester.tap(photo);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
        final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save').last,
        );
        if (save.onPressed != null) {
          ready = true;
          break;
        }
      }
      // Wait for the import itself: an existing file does not mean that the
      // form has finished loading its photo and can handle Cancel yet.
      expect(ready, isTrue, reason: 'The catalog photo import did not finish');
      expect(await store.names(), hasLength(1));
    });
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keep-editing')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keep-editing')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => expect(await store.names(), hasLength(1)),
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discard-changes')));
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsNothing);
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && (await store.names()).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await store.names(), isEmpty);
    });
    await finish(tester);
  });
}

class _DelayedLoffeeApi extends FakeLoffeeApi {
  final response = Completer<LoffeePage>();

  @override
  Future<LoffeePage> search({
    required String key,
    required String query,
    int page = 1,
  }) => response.future;
}
