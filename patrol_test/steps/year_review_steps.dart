import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';
import 'package:patrol/patrol.dart';

Future<void> checkYearReview(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'A year of coffee',
    roaster: 'Year roaster',
    country: 'Colombia',
  );
  final now = DateTime.now();
  final id = await repository.createBrew(
    coffeeId: coffee,
    methodName: 'V60',
    doseGrams: 15,
    brewedAt: DateTime(now.year, 1, 2),
  );
  await repository.rateBrew(
    id,
    rating: 9,
    notes: 'Private note stays in the diary',
    tasting: const BrewTasting(),
  );
  await repository.createBrew(
    coffeeId: coffee,
    methodName: 'V60',
    brewedAt: DateTime(now.year - 1, 5),
  );
  final before = await repository.allBrews();
  Uint8List? exported;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(call.method, 'share');
        expect(args['mimeTypes'], ['image/png']);
        exported = await File((args['paths'] as List<dynamic>).single as String)
            .readAsBytes();
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await $.tap(find.byTooltip('Stats'));
    await $.tap(find.byKey(const ValueKey('stats-year-review')));
    expect(find.text('1 / 8'), findsOneWidget);
    await $.takeNativeScreenshot('year-review-intro');
    await $.tester.drag(find.byType(PageView), const Offset(-320, 0));
    await $.pumpAndSettle();
    expect(find.text('The world,\nin your cup.'), findsOneWidget);
    await $.tap(find.byKey(const ValueKey('year-previous')));
    for (var i = 0; i < 7; i++) {
      await $.tap(find.byKey(const ValueKey('year-next')));
    }
    await $.tester.scrollUntilVisible(
      find.byKey(const ValueKey('year-share')),
      240,
      scrollable: find
          .descendant(
            of: find.byType(YearStoryView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('year-share')));
    expect(find.text('Private note stays in the diary'), findsNothing);
    await $.takeNativeScreenshot('year-review-share');
    await $.tap(find.byKey(const ValueKey('year-share-confirm')));
    for (var i = 0; exported == null && i < 80; i++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(exported, isNotNull);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1120);
    expect(frame.image.height, greaterThan(800));
    frame.image.dispose();
    codec.dispose();
    Navigator.of(
      $.tester.element(find.byKey(const ValueKey('year-share-confirm'))),
    ).pop();
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('year-selector')));
    await $.tap(find.text('${now.year - 1}').last);
    expect(find.text('January 1 – December 31'), findsOneWidget);
    expect(find.text('1 / 7'), findsOneWidget);
    expect(await repository.allBrews(), before);
    await $.takeNativeScreenshot('year-review-previous-year');
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}
