import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:patrol/patrol.dart';

Future<void> checkShareCharts(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final coffee = await repo.createCoffee(
    name: 'Patrol chart coffee',
    roaster: 'Fixture',
  );
  final photoDirectory = await Directory.systemTemp.createTemp('share-photo-');
  final photos = PhotoStore(photoDirectory);
  final photoName = await photos.add(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
    ),
  );
  await repo.setCoffeePhotos(coffee, [photoName]);
  final settings = BrewParameterSettings(database);
  const fields = {
    BrewParameter.coffee,
    BrewParameter.dose,
    BrewParameter.beverage,
    BrewParameter.tds,
  };
  await settings.saveShared(fields);
  final templates = ShareTemplateSettings(database);
  await templates.saveTemplate(
    const ShareTemplate(
      id: 'espresso-chart',
      name: 'My espresso',
      style: ShareTemplateStyle.espresso,
      body: 'My <method>: <time> at <ratio>.',
    ),
  );
  await templates.select(ShareTemplateStyle.espresso, 'espresso-chart');
  Uint8List? exported;
  String? caption;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(args['mimeTypes'], ['image/png']);
        caption = args['text'] as String?;
        exported = await File((args['paths'] as List<dynamic>).single as String)
            .readAsBytes();
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  try {
    for (final espresso in [true, false]) {
      final id = await repo.createBrew(
        coffeeId: coffee,
        methodName: espresso ? 'Espresso' : 'V60',
        doseGrams: 18,
        beverageGrams: espresso ? 36 : 270,
        timeSeconds: espresso ? 30 : 180,
        tdsPercent: espresso ? 10 : 1.35,
      );
      if (espresso) await repo.setBrewPhotos(id, [photoName]);
      // Espresso has its own cover; filter exercises the coffee fallback.
      if (espresso) await repo.setCoffeePhotos(coffee, []);
      if (!espresso) await repo.setCoffeePhotos(coffee, [photoName]);
      await repo.saveScaleCurve(
        id,
        ShotCurve(
          timesMs: espresso
              ? [0, 5000, 10000, 15000, 20000, 30000]
              : [0, 10000, 30000, 60000, 120000, 180000],
          pressure: espresso ? [0, 3, 8.5, 9, 8, 6] : [],
          flow: [0, 1, 2, 1.8, 1.6, 1],
          weight: espresso ? [0, 3, 8, 17, 25, 36] : [0, 30, 70, 130, 210, 270],
        ),
      );
      await $.pumpWidgetAndSettle(
        HolyBeansApp(
          database: database,
          photos: photos,
          initialLocale: const Locale('en'),
        ),
      );
      final navigation = $.tester.getRect(find.byType(NavigationBar));
      await $.tester.tapAt(
        Offset(
          navigation.left + navigation.width * 2.5 / 4,
          navigation.center.dy,
        ),
      );
      await $.pumpAndSettle();
      await $.tap(find.byTooltip('Actions').first);
      await $.tap(find.text('Share brew'));
      expect(
        $.tester
            .widget<ShareBrewSheet>(find.byType(ShareBrewSheet))
            .initialPhoto,
        await photos.file(photoName).readAsBytes(),
      );
      await $.tap(find.text('Image'));
      if (espresso) {
        await $.tap(find.byKey(const ValueKey('share-photo-caption')));
        expect(find.text('Change photo'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('share-photo-card')),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
      }
      for (final key in ['share-include-curve', 'share-include-map']) {
        final option = find.byKey(ValueKey(key));
        await $.scrollUntilVisible(finder: option);
        expect($.tester.widget<CheckboxListTile>(option).value, isFalse);
        await $.tap(option);
      }
      final card = find.byKey(
        ValueKey(espresso ? 'share-photo-card' : 'brew-share-card'),
      );
      final map = find.byKey(
        ValueKey(espresso ? 'espresso-map' : 'sensory-map-chart'),
      );
      expect(map, findsOneWidget);
      final height = $.tester.getSize(card).height;
      await $.scrollUntilVisible(
        finder: find.byKey(const ValueKey('share-extraction-chart')),
      );
      await $.takeNativeScreenshot(
        espresso ? 'share-espresso-pressure' : 'share-filter-curve',
      );
      await $.scrollUntilVisible(finder: map);
      await $.takeNativeScreenshot(
        espresso ? 'share-espresso-map' : 'share-filter-sensory-map',
      );
      exported = null;
      await $.tap(find.byKey(const ValueKey('share-confirm')));
      for (var attempt = 0; exported == null && attempt < 50; attempt++) {
        await $.pump(const Duration(milliseconds: 100));
      }
      expect(exported, isNotNull);
      expect(caption, espresso ? 'My Espresso: 0:30 at 1:2.' : null);
      final codec = await ui.instantiateImageCodec(exported!);
      final frame = await codec.getNextFrame();
      expect(frame.image.height, closeTo(height * 3, 1));
      expect(height, greaterThan(700));
      frame.image.dispose();
      codec.dispose();
      expect(await settings.loadShared(), fields);
      await $.pumpWidgetAndSettle(const SizedBox.shrink());
    }
    expect((await database.select(database.brews).get()).length, 2);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await photoDirectory.delete(recursive: true);
  }
}
