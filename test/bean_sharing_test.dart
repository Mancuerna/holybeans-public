import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_import.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';

const _geisha = SharedBean(
  name: 'Abu Coffee Geisha',
  roaster: 'Kima Coffee',
  roastLevel: 'light',
  flavorNotes: ['Mango', 'raspberry'],
  shopUrl: 'https://kima.example/geisha',
  priceCents: 796,
  bagGrams: 50,
  origins: [SharedOrigin(country: 'Panama', region: 'Boquete')],
);

const _pink = SharedBean(name: 'Pink Bourbon', roaster: 'Guido Coffee');

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  /// Opens the app as if Android launched it with [text]; [scan] answers
  /// the QR scanner.
  Future<void> launchWith(
    WidgetTester tester,
    String text, {
    Future<String?> Function()? scan,
    String language = 'en',
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('holybeans/incoming');
    var taken = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'scan') return scan?.call();
      if (call.method != 'take' || taken) return null;
      taken = true;
      return text;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      HolyBeansApp(
        database: database,
        initialLocale: Locale(language),
        incoming: IncomingShares(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('invalid pasted text never opens a form or writes a coffee', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await launchWith(tester, '');
    await tester.tap(find.byKey(const ValueKey('bean-add-options')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('import-paste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-paste')));
    await tester.pumpAndSettle();
    // A real keyboard removes the floating button and its local context.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paste-text')),
      '{"name":',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('paste-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paste-dialog')), findsOneWidget);
    final strings = AppLocalizations.of(
      tester.element(find.byKey(const ValueKey('paste-dialog'))),
    )!;
    expect(find.text(strings.importInvalidJson), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paste-text')))
          .controller!
          .text,
      '{"name":',
    );
    expect(find.byType(CoffeeForm), findsNothing);
    expect(await database.select(database.coffees).get(), isEmpty);
    expect(await database.select(database.coffeeLots).get(), isEmpty);
    for (final sample in [
      ('{"beans":[]}', strings.importNothing),
      ('{"version":99,"beans":[]}', strings.importNewer),
    ]) {
      await tester.enterText(
        find.byKey(const ValueKey('paste-text')),
        sample.$1,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('paste-import')));
      await tester.pumpAndSettle();
      expect(find.text(sample.$2), findsOneWidget);
      expect(find.byKey(const ValueKey('paste-dialog')), findsOneWidget);
    }
    await tester.enterText(
      find.byKey(const ValueKey('paste-text')),
      encodeBeans([_geisha]),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('paste-import')));
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsOneWidget);
    expect(await database.select(database.coffees).get(), isEmpty);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await finish(tester);
  });

  for (final language in ['en', 'es']) {
    for (final review in [false, true]) {
      testWidgets(
        'single-card dropped fields require review ($language, $review)',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await launchWith(
            tester,
            '{"name":"Review","roaster":"R","price":"12 euros + 3 shipping","roastDate":"2026-02-30"}',
            language: language,
          );
          final dialog = find.byKey(const ValueKey('import-dropped'));
          expect(dialog, findsOneWidget);
          final strings = AppLocalizations.of(tester.element(dialog))!;
          expect(find.textContaining(strings.paidPrice), findsOneWidget);
          expect(find.textContaining(strings.roastDate), findsOneWidget);
          expect(find.byType(CoffeeForm), findsNothing);
          expect(await database.select(database.coffees).get(), isEmpty);
          await tester.tap(
            review
                ? find.byKey(const ValueKey('import-dropped-review'))
                : find.text(strings.cancel),
          );
          await tester.pumpAndSettle();
          if (review) {
            expect(find.byType(CoffeeForm), findsOneWidget);
            await tester.tap(find.text(strings.cancel).last);
            await tester.pumpAndSettle();
          }
          expect(find.byType(CoffeeForm), findsNothing);
          expect(await database.select(database.coffees).get(), isEmpty);
          expect(await database.select(database.coffeeLots).get(), isEmpty);
          await finish(tester);
        },
      );
    }
  }

  testWidgets('reviewing and cancelling a shared card writes no journal rows', (
    tester,
  ) async {
    await launchWith(tester, encodeBeans([_geisha]));
    expect(find.byType(CoffeeForm), findsOneWidget);
    expect(await database.select(database.coffees).get(), isEmpty);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsNothing);
    expect(await database.select(database.coffees).get(), isEmpty);
    expect(await database.select(database.coffeeLots).get(), isEmpty);
    expect(await database.select(database.coffeeComponents).get(), isEmpty);
    await finish(tester);
  });

  testWidgets('a shared card opens the coffee form filled in', (tester) async {
    await launchWith(tester, encodeBeans([_geisha]));
    expect(find.byType(CoffeeForm), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Abu Coffee Geisha'), findsOne);
    expect(find.widgetWithText(TextFormField, 'Kima Coffee'), findsOne);

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final coffee = await database.select(database.coffees).getSingle();
    expect((coffee.paidPriceCents, coffee.roastLevel), (796, 'light'));
    expect(coffee.shopUrl, 'https://kima.example/geisha');
    final lot = (await repository.coffeeLots(coffee.id)).single;
    expect(lot.initialGrams, 50);
    final origin = (await repository.coffeeComponents(coffee.id)).single;
    expect((origin.country, origin.region), ('Panama', 'Boquete'));
    await finish(tester);
  });

  testWidgets('a coffee already in the journal is not added twice unasked', (
    tester,
  ) async {
    await repository.createCoffee(name: 'ABU coffee geisha', roaster: 'Kima');
    await repository.createCoffee(
      name: 'Abu Coffee Geisha',
      roaster: 'Kima Coffee',
    );
    await launchWith(tester, beanQrText(_geisha));
    expect(find.byKey(const ValueKey('import-duplicate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-add-anyway')));
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsOneWidget);
    await finish(tester);
  });

  testWidgets('several coffees are reviewed, known ones unticked', (
    tester,
  ) async {
    await repository.createCoffee(
      name: 'Abu Coffee Geisha',
      roaster: 'Kima Coffee',
    );
    await launchWith(tester, '''
```json
[
  ${encodeBeans([_geisha]).replaceAll(RegExp(r'^\{[\s\S]*"beans": \[|\]\s*\}$'), '')},
  {"name": "Pink Bourbon", "roaster": "Guido", "roastDate": "soon"}
]
```''');
    expect(find.byType(BeanImportPage), findsOneWidget);
    final first = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('import-bean-0')),
    );
    expect(first.value, isFalse, reason: 'already in the journal');
    expect(find.text('Already in your journal'), findsOneWidget);
    expect(find.text('Not read: Roast date'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-beans-confirm')));
    await tester.pumpAndSettle();
    final names = [
      for (final coffee in await database.select(database.coffees).get())
        coffee.name,
    ];
    expect(names, unorderedEquals(['Abu Coffee Geisha', 'Pink Bourbon']));
    expect(find.text('1 coffee imported'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('text that is not a card says so', (tester) async {
    await launchWith(tester, 'Just a shopping list: milk, bread');
    expect(find.byType(CoffeeForm), findsNothing);
    expect(
      find.text(
        'This card could not be read. Check that you copied the complete JSON.',
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('the scan shortcut says when the QR scanner cannot open', (
    tester,
  ) async {
    await launchWith(
      tester,
      'holybeans://shortcut/scan-bean',
      scan: () async => throw PlatformException(
        code: 'scan_failed',
        message: 'Play services missing',
      ),
    );
    expect(find.text('Could not open the QR scanner.'), findsOneWidget);
    expect(find.byType(CoffeeForm), findsNothing);
    await finish(tester);
  });

  testWidgets('a coffee shares its card as a QR code and a file', (
    tester,
  ) async {
    final id = await repository.createCoffee(
      name: 'Abu Coffee Geisha',
      roaster: 'Kima Coffee',
      initialGrams: 50,
      paidPriceCents: 796,
    );
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await launchWith(tester, '');
    final bar = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(Offset(bar.left + bar.width * 1.5 / 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('bean-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bean-share-card')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('bean-share-confirm'))).bottom,
      lessThanOrEqualTo(900 - 48),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('bean-share-transfer')),
    );
    await tester.tap(find.byKey(const ValueKey('bean-share-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-bean-qr')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-bean-file')), findsOneWidget);
    final qrButton = find.byKey(const ValueKey('share-bean-qr-image'));
    await tester.ensureVisible(qrButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(qrButton).bottom, lessThanOrEqualTo(900 - 48));
    await finish(tester);
  });

  testWidgets('pasting reads the clipboard, or takes what is typed in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    String? clipboard = encodeBeans([_geisha, _pink]);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' && clipboard != null
          ? {'text': clipboard}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    Future<void> paste() async {
      await tester.tap(find.byKey(const ValueKey('bean-add-options')));
      await tester.pumpAndSettle();
      final pasteTile = find.byKey(const ValueKey('import-paste'));
      await tester.ensureVisible(pasteTile);
      await tester.pumpAndSettle();
      await tester.tap(pasteTile);
      await tester.pumpAndSettle();
    }

    // The clipboard can be read: the box comes filled in.
    await paste();
    expect(find.byKey(const ValueKey('paste-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paste-import')));
    await tester.pumpAndSettle();
    expect(find.byType(BeanImportPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The pasted text stays unchanged; the reader recovers chat escapes.
    clipboard = r'{"name":"Hugo Pareja \[SL9\]","origins":\[\]}';
    await paste();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paste-text')))
          .controller!
          .text,
      clipboard,
    );
    await tester.tap(find.byKey(const ValueKey('paste-import')));
    await tester.pumpAndSettle();
    expect(find.text('Hugo Pareja [SL9]'), findsWidgets);
    expect(find.byType(CoffeeForm), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // It cannot: the box waits for the person to paste.
    clipboard = null;
    await paste();
    final import = find.byKey(const ValueKey('paste-import'));
    expect(tester.widget<FilledButton>(import).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('paste-text')),
      'not a coffee card',
    );
    await tester.pump();
    await tester.tap(import);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This card could not be read. Check that you copied the complete JSON.',
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  test('the AI instructions carry a card HolyBeans reads', () {
    final read = readBeans(aiCardExample).single;
    expect(read.dropped, isEmpty);
    expect(read.bean.origins.single.altitudeMeters, 1800);
  });
}
