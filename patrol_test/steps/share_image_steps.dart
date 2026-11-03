import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

Future<void> checkShareImage(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Patrol image pours',
    roaster: 'Fixture',
  );
  await repository.createBrew(
    coffeeId: coffee,
    methodName: 'V60',
    doseGrams: 18,
    waterGrams: 288,
    notes: 'First line\nLast line: still notes',
    pours: BrewPours(
      bloomCount: 2,
      pourCount: 10,
      phases: [
        for (var n = 1; n <= 2; n++)
          BrewPourPhase(
            kind: BrewPourKind.bloom,
            number: n,
            waterGrams: 30,
            durationSeconds: 10,
            restSeconds: 20,
          ),
        for (var n = 1; n <= 10; n++)
          BrewPourPhase(
            kind: BrewPourKind.pour,
            number: n,
            waterGrams: 22.8,
            durationSeconds: 10,
          ),
      ],
    ),
  );
  final settings = BrewParameterSettings(database);
  const fields = {
    BrewParameter.coffee,
    BrewParameter.method,
    BrewParameter.dose,
    BrewParameter.water,
    BrewParameter.pourDetails,
    BrewParameter.notes,
  };
  await settings.saveShared(fields);
  Uint8List? exported;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  // Capture the file at the platform boundary without sending it to anyone.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'share');
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(args['mimeTypes'], ['image/png']);
        exported = await File((args['paths'] as List<dynamic>).single as String)
            .readAsBytes();
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    final navigation = $.tester.getRect(find.byType(NavigationBar));
    await $.tester.tapAt(
      Offset(
        navigation.left + navigation.width * 2.5 / 4,
        navigation.center.dy,
      ),
    );
    await $.pumpAndSettle();
    await $.tap(find.byTooltip('Actions'));
    await $.tap(find.text('Share brew'));
    await $.tap(find.text('Image'));
    final card = find.byKey(const ValueKey('brew-share-card'));
    for (final phase in ['Bloom 1', 'Bloom 2', 'Pour 10']) {
      expect(
        find.descendant(of: card, matching: find.textContaining(phase)),
        findsOneWidget,
      );
    }
    final height = $.tester.getSize(card).height;
    await $.takeNativeScreenshot('share-image-first-blooms');
    await $.scrollUntilVisible(
      finder: find.text('First line\nLast line: still notes'),
    );
    await $.takeNativeScreenshot('share-image-last-pour');
    await $.tap(find.byKey(const ValueKey('share-confirm')));
    for (var attempt = 0; exported == null && attempt < 50; attempt++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(exported, isNotNull);
    expect(exported!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    expect(frame.image.height, closeTo(height * 3, 1));
    frame.image.dispose();
    codec.dispose();
    expect(await settings.loadShared(), fields);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}
