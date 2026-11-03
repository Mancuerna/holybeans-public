import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

Future<void> checkBeanShare(PatrolIntegrationTester $, AppDatabase db) async {
  final repo = JournalRepository(db);
  final id = await repo.createCoffee(
    name: 'Share Geisha',
    roaster: 'Fixture',
    initialGrams: 250,
    paidPriceCents: 1800,
    notes: 'Personal note',
  );
  final directory = await Directory.systemTemp.createTemp('bean-share-');
  final photos = PhotoStore(directory);
  final name = await photos.add(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
    ),
  );
  await repo.setCoffeePhotos(id, [name]);
  final before = await db.select(db.coffees).getSingle();
  final lots = await repo.coffeeLots(id);
  final calls = <Map<dynamic, dynamic>>[];
  final images = <Uint8List>[];
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        calls.add(args);
        if (args['mimeTypes'] != null) {
          expect(args['mimeTypes'], ['image/png']);
          images.add(
            await File((args['paths'] as List<dynamic>).single as String)
                .readAsBytes(),
          );
        }
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        database: db,
        photos: photos,
        initialLocale: const Locale('en'),
      ),
    );
    final bar = $.tester.getRect(find.byType(NavigationBar));
    await $.tester.tapAt(Offset(bar.left + bar.width * 1.5 / 4, bar.center.dy));
    await $.pumpAndSettle();
    Future<void> open() async {
      await $.tap(find.byKey(ValueKey('bean-menu-$id')));
      await $.tap(find.byKey(const ValueKey('bean-share-card')));
    }

    for (final mode in ['text', 'card', 'photo']) {
      await open();
      if (mode != 'text') {
        await $.tap(find.text('Image'));
        if (mode == 'card') {
          await $.tap(find.text('Change photo'));
          await $.tap(find.text('Take photo'));
          await Future<void>.delayed(const Duration(seconds: 2));
          await $.takeNativeScreenshot('bean-share-native-camera');
          await $.platformAutomator.android.pressBack();
          await $.waitUntilVisible(find.text('Change photo'));
          await $.tap(find.text('Change photo'));
          await $.tap(find.text('Choose from gallery'));
          await Future<void>.delayed(const Duration(seconds: 2));
          await $.takeNativeScreenshot('bean-share-native-gallery');
          await $.platformAutomator.android.pressBack();
          await $.waitUntilVisible(find.text('Change photo'));
        }
        if (mode == 'photo') {
          await $.tap(find.byKey(const ValueKey('bean-share-photo-caption')));
        }
      }
      await $.takeNativeScreenshot('bean-share-$mode');
      await $.tap(find.byKey(const ValueKey('bean-share-confirm')));
      for (
        var i = 0;
        calls.length <= ['text', 'card', 'photo'].indexOf(mode) && i < 50;
        i++
      ) {
        await $.pump(const Duration(milliseconds: 100));
      }
      final caption = calls.last['text'] as String?;
      if (mode == 'card') {
        expect(caption, isNull);
      } else {
        expect(caption, contains('Share Geisha'));
        expect(caption, isNot(contains('Personal note')));
        expect(caption, isNot(contains('250')));
        expect(caption, isNot(contains('18')));
      }
    }
    expect(calls, hasLength(3));
    expect(images, hasLength(2));
    for (final bytes in images) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(500));
      frame.image.dispose();
      codec.dispose();
    }
    await open();
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('bean-share-transfer')),
    );
    await $.tap(find.byKey(const ValueKey('bean-share-transfer')));
    expect(find.byKey(const ValueKey('share-bean-qr')), findsOneWidget);
    await $.platformAutomator.android.pressBack();
    await $.pumpAndSettle();
    expect(await db.select(db.coffees).getSingle(), before);
    expect(await repo.coffeeLots(id), lots);
    expect(await repo.coffeePhotos(id), [name]);
    expect(photos.file(name).existsSync(), isTrue);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await directory.delete(recursive: true);
  }
}
