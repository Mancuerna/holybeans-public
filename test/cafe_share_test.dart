import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_share_card.dart';
import 'package:holybeans/ui/cafes/cafe_share_sheet.dart';
import 'package:holybeans/ui/cafes/cafe_share_text.dart';
import 'package:holybeans/ui/cafes/cafes_page.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

const _cafe = Cafe(
  id: 'cafe',
  name: 'Hola Coffee Lagasca',
  city: 'Madrid',
  country: 'España',
  createdAtMs: 0,
  updatedAtMs: 0,
);
final _drink = CafeDrink(
  id: 'drink',
  cafeId: 'cafe',
  drinkType: 'Flat white',
  coffeeName: 'Kuria',
  originCountry: 'Kenia',
  process: 'Washed',
  variety: 'SL28',
  notes: 'Private note',
  rating: 8.5,
  priceCents: 450,
  currency: 'USD',
  drankAtMs: DateTime(2026, 10, 23).millisecondsSinceEpoch,
  createdAtMs: 0,
  updatedAtMs: 0,
);
final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
);

void main() {
  testWidgets('a minimal drink shares only known values', (tester) async {
    late List<CafeShareRow> rows;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            rows = cafeShareRows(
              context,
              const Cafe(
                id: 'minimal',
                name: 'Only cafe',
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
              const CafeDrink(
                id: 'minimal-drink',
                cafeId: 'minimal',
                drinkType: 'Espresso',
                currency: 'EUR',
                drankAtMs: 0,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
              null,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(rows.map((row) => row.id), ['cafe', 'drink', 'date']);
    expect(
      cafeShareText(rows, {'cafe', 'drink'}),
      'Café: Only cafe\nDrink or method: Espresso',
    );
  });

  for (final (language, asImage) in [
    ('en', false),
    ('en', true),
    ('es', false),
    ('es', true),
  ]) {
    testWidgets(
      'cafe sharing respects privacy and exports $language $asImage',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final s = lookupAppLocalizations(Locale(language));
        CafeShareResult? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    result = await showModalBottomSheet<CafeShareResult>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CafeShareSheet(
                        rows: cafeShareRows(
                          context,
                          _cafe,
                          _drink,
                          'Ineffable',
                        ),
                        initialPhoto: _photo,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Private note'), findsNothing);
        expect(
          find.textContaining(
            formatRegionalDate(
              DateTime.fromMillisecondsSinceEpoch(_drink.drankAtMs),
              regionalLocale,
            ),
          ),
          findsNothing,
        );
        expect(find.textContaining('8.5'), findsNothing);
        expect(find.textContaining('8,5'), findsNothing);
        expect(find.textContaining('USD'), findsNothing);

        if (asImage) {
          await tester.tap(find.text(s.shareFormatImage));
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('cafe-share-card-preview'));
          expect(
            find.descendant(of: card, matching: find.text(s.appTitle)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text(_cafe.name)),
            findsOneWidget,
          );
          expect(
            tester.widget<CafeShareCard>(find.byType(CafeShareCard)).photo,
            isNull,
          );
          await tester.tap(
            find.byKey(const ValueKey('cafe-share-include-photo')),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<CafeShareCard>(find.byType(CafeShareCard)).photo,
            _photo,
          );
        }

        await tester.ensureVisible(find.text(s.shareFields));
        await tester.tap(find.text(s.shareFields));
        await tester.pumpAndSettle();
        for (final id in ['date', 'rating', 'price', 'notes']) {
          final field = find.byKey(ValueKey('cafe-share-field-$id'));
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
        }
        if (asImage) {
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('cafe-share-card-preview')),
              matching: find.textContaining('Private note'),
            ),
            findsOneWidget,
          );
        }

        await tester.runAsync(() async {
          final button = tester.widget<FilledButton>(
            find.byKey(const ValueKey('cafe-share-confirm')),
          );
          button.onPressed!();
          button.onPressed!();
          for (var attempt = 0; result == null && attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        if (asImage) {
          expect(result!.text, isNull);
          expect(result!.image, isNotNull);
          await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(result!.image!);
            final frame = await codec.getNextFrame();
            expect(frame.image.width, greaterThan(500));
            expect(frame.image.height, greaterThan(50));
            frame.image.dispose();
            codec.dispose();
          });
        } else {
          expect(result!.image, isNull);
          final text = result!.text!;
          expect(text, contains(_cafe.name));
          expect(text, contains('Private note'));
          expect(
            text,
            contains(
              formatRegionalDate(
                DateTime.fromMillisecondsSinceEpoch(_drink.drankAtMs),
                regionalLocale,
              ),
            ),
          );
          final expectedRating = language == 'en' ? '8.5' : '8,5';
          final expectedPrice = language == 'en' ? '\$4.50' : '4,50\u00a0\$';
          expect(text, contains(expectedRating));
          expect(text, contains(expectedPrice));
          expect(text, isNot(contains('€')));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('CafesPage exports text and a photo PNG without changing data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final directory = Directory.systemTemp.createTempSync('cafe-share-flow');
    addTearDown(() => directory.deleteSync(recursive: true));
    final photos = PhotoStore(directory);
    final repository = CafeRepository(db);
    late String photoName;
    await tester.runAsync(() async {
      photoName = await photos.add(_photo);
      await repository.save(
        CafeDrinkInput(
          cafe: const CafeInput(
            name: 'Hola Coffee Lagasca',
            city: 'Madrid',
            country: 'España',
          ),
          drinkType: 'V60',
          drankAt: DateTime(2026, 10, 23),
          roaster: 'Ineffable',
          coffeeName: 'Kuria',
          originCountry: 'Kenia',
          notes: 'Private note',
          rating: 8,
          priceCents: 450,
          photos: [photoName],
        ),
      );
    });
    final before = await repository.read();
    final drink = before.drinks.single;
    final calls = <Map<dynamic, dynamic>>[];
    final images = <Uint8List>[];
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        null,
      ),
    );
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final args = call.arguments as Map<dynamic, dynamic>;
      calls.add(args);
      if (args['paths'] case final List<dynamic> paths) {
        images.add(await File(paths.single as String).readAsBytes());
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CafesPage(repository: repository, photos: photos),
      ),
    );
    await tester.pumpAndSettle();
    final shareButton = find.byKey(ValueKey('cafe-share-${drink.id}'));
    await tester.tap(shareButton);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        find.byType(CafeShareSheet).evaluate().isEmpty && attempt < 100;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(CafeShareSheet), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('cafe-share-confirm')));
      for (var attempt = 0; calls.isEmpty && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single['text'], contains(_cafe.name));
    expect(calls.single['text'], isNot(contains('Private note')));
    expect(calls.single['paths'], isNull);

    await tester.tap(shareButton);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        find.byType(CafeShareSheet).evaluate().isEmpty && attempt < 100;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cafe-share-include-photo')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('cafe-share-confirm')));
      for (
        var attempt = 0;
        (calls.length < 2 || images.isEmpty) && attempt < 100;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last['mimeTypes'], ['image/png']);
    expect(
      (calls.last['paths'] as List).single,
      endsWith('holybeans-cafe-drink.png'),
    );
    expect(images, hasLength(1));
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(images.single);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(500));
      frame.image.dispose();
      codec.dispose();
    });
    final after = await repository.read();
    expect(after.cafes, before.cafes);
    expect(after.drinks, before.drinks);
    expect(after.roasters, before.roasters);
    expect(after.photos, before.photos);
    expect(photos.file(photoName).existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cafe ratings and amounts follow the Spanish region', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = CafeRepository(db);
    for (final rating in [8.5, 7.5]) {
      await repository.save(
        CafeDrinkInput(
          cafe: const CafeInput(name: 'Regional cafe'),
          drinkType: 'Espresso',
          drankAt: DateTime(2026, 10, 24),
          rating: rating,
          priceCents: 450,
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'ES'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CafesPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    final s = lookupAppLocalizations(const Locale('es', 'ES'));
    final title = find.text('Regional cafe\u00a0· Espresso').first;
    final titleText = tester.widget<Text>(title).data!;
    final separator = titleText.indexOf('·');
    final box = tester
        .renderObject<RenderParagraph>(title)
        .getBoxesForSelection(
          TextSelection(baseOffset: separator, extentOffset: separator + 1),
        )
        .single;
    expect(box.top, greaterThan(0));
    expect(box.left, greaterThan(0));
    expect(find.textContaining('${s.rating}: 8,5'), findsOneWidget);
    expect(find.textContaining('${s.rating}: 8.5'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cafe-stats-tab')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('8,0'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('8,0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('9,00\u00a0€'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('9,00\u00a0€'), findsOneWidget);
    expect(find.textContaining('${s.cafePriceTotal} · EUR'), findsOneWidget);
    expect(find.text('EUR9.00'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
