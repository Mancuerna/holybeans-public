import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

Future<void> checkCafeShare(PatrolIntegrationTester $, AppDatabase db) async {
  final repository = CafeRepository(db);
  final directory = await Directory.systemTemp.createTemp('cafe-share-');
  final photos = PhotoStore(directory);
  final photoName = await photos.add(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
    ),
  );
  await repository.save(
    CafeDrinkInput(
      cafe: const CafeInput(
        name: 'Patrol Cafe',
        city: 'Madrid',
        country: 'España',
      ),
      drinkType: 'Flat white',
      drankAt: DateTime(2026, 10, 24),
      roaster: 'Ineffable',
      coffeeName: 'Kuria',
      originCountry: 'Kenia',
      process: 'Washed',
      variety: 'SL28',
      notes: 'Private note',
      rating: 8.5,
      priceCents: 450,
      photos: [photoName],
    ),
  );
  final before = await repository.read();
  final drink = before.drinks.single;
  final calls = <Map<dynamic, dynamic>>[];
  final images = <Uint8List>[];
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        calls.add(args);
        if (args['paths'] case final List<dynamic> paths) {
          images.add(await File(paths.single as String).readAsBytes());
        }
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        services: AppServices(database: db, photos: photos),
        initialLocale: const Locale('en'),
      ),
    );
    await $.tap(find.byKey(const ValueKey('cafes-button')));
    final shareButton = find.byKey(ValueKey('cafe-share-${drink.id}'));
    await $.tap(shareButton);
    expect(find.textContaining('Private note'), findsNothing);
    await $.takeNativeScreenshot('cafe-share-text');
    await $.tap(find.byKey(const ValueKey('cafe-share-confirm')));
    for (var attempt = 0; calls.isEmpty && attempt < 50; attempt++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(calls, hasLength(1));
    expect(calls.single['text'], contains('Patrol Cafe'));
    expect(calls.single['text'], contains('Flat white'));
    expect(calls.single['text'], isNot(contains('Private note')));
    expect(calls.single['paths'], isNull);

    await $.tap(shareButton);
    await $.tap(find.text('Image'));
    expect(find.text('HolyBeans'), findsOneWidget);
    expect(find.textContaining('Private note'), findsNothing);
    await $.tap(find.byKey(const ValueKey('cafe-share-include-photo')));
    await $.takeNativeScreenshot('cafe-share-image');
    await $.tap(find.byKey(const ValueKey('cafe-share-confirm')));
    for (
      var attempt = 0;
      (calls.length < 2 || images.isEmpty) && attempt < 50;
      attempt++
    ) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(calls, hasLength(2));
    expect(calls.last['text'], isNull);
    expect(calls.last['mimeTypes'], ['image/png']);
    expect(
      (calls.last['paths'] as List).single,
      endsWith('holybeans-cafe-drink.png'),
    );
    expect(images, hasLength(1));
    final codec = await ui.instantiateImageCodec(images.single);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(500));
    expect(frame.image.height, greaterThan(50));
    frame.image.dispose();
    codec.dispose();

    final after = await repository.read();
    expect(after.cafes, before.cafes);
    expect(after.drinks, before.drinks);
    expect(after.roasters, before.roasters);
    expect(after.photos, before.photos);
    expect(photos.file(photoName).existsSync(), isTrue);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await directory.delete(recursive: true);
  }
}
