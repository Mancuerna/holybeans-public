import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/ui/year_review/year_review_card.dart';
import 'package:holybeans/ui/year_review/year_review_page.dart';
import 'package:holybeans/ui/year_review/year_review_previews.dart';
import 'package:holybeans/ui/year_review/year_review_share.dart';
import 'package:holybeans/ui/year_review/year_review_story.dart';

import 'helpers/ui_test_support.dart';
import 'helpers/year_fixture.dart';

Widget app(Widget home) => localizedApp(
  locale: const Locale('en'),
  home: Scaffold(body: home),
);

void main() {
  testWidgets('details are available separately and money stays optional', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        YearReviewPage(
          now: DateTime(2026, 10),
          brews: [yearBrew('a', DateTime(2026), dose: 18, rating: 9)],
          coffees: [yearCoffee('a', paidPriceCents: 1200)],
          components: yearComponents,
          methods: yearMethods,
          lots: [yearLot('a')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 8'), findsOneWidget);
    expect(find.textContaining('archived and imported'), findsNothing);
    // Sharing is available immediately, without completing the recap.
    await tester.tap(find.byKey(const ValueKey('year-share')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<YearExportCard>(find.byType(YearExportCard)).story,
      YearStory.intro,
    );
    Navigator.of(tester.element(find.byType(YearExportCard))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('year-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About these numbers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('archived and imported'), findsOneWidget);
    Navigator.of(tester.element(find.text('About these numbers'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('year-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My coffee spending'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<YearStory>), findsOneWidget);
    expect(find.textContaining('Among coffees bought'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team copy requires a dominant method; ties stay explicit', (
    tester,
  ) async {
    final sample = sampleCoffeeYear();
    await tester.pumpWidget(
      app(YearExportCard(year: sample, story: YearStory.method)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team V60.'), findsOneWidget);
    final tied = CoffeeYear(
      year: 2025,
      now: DateTime(2026),
      brews: sample.entries.take(2).toList(),
      coffees: const [],
      components: const [],
      methods: const [],
    );
    await tester.pumpWidget(
      app(YearExportCard(year: tied, story: YearStory.method)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Team '), findsNothing);
    expect(find.text('Joint No. 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'carousel exports selected cards in order as distinct 1080x1920 PNGs',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('year-share-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory.path,
      );
      final calls = <Map<dynamic, dynamic>>[];
      final images = <Uint8List>[];
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        for (final path in args['paths'] as List<dynamic>) {
          images.add(await File(path as String).readAsBytes());
        }
        calls.add(args);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
      });
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => shareCoffeeYear(
                context,
                sampleCoffeeYear(),
                story: YearStory.intro,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('year-pick-origins')));
      await tester.pumpAndSettle();
      expect(find.text('Share 2 cards'), findsOneWidget);
      expect(
        tester.widget<YearExportCard>(find.byType(YearExportCard)).story,
        YearStory.origins,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('year-share-confirm')));
        for (var i = 0; calls.isEmpty && i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single['mimeTypes'], ['image/png', 'image/png']);
      final paths = calls.single['paths'] as List<dynamic>;
      expect(paths[0], endsWith('holybeans-2025-intro.png'));
      expect(paths[1], endsWith('holybeans-2025-origins.png'));
      expect(images, hasLength(2));
      expect(images[0], isNot(orderedEquals(images[1])));
      await tester.runAsync(() async {
        for (final bytes in images) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1080);
          expect(frame.image.height, 1920);
          frame.image.dispose();
          codec.dispose();
        }
      });
      expect(
        tester
            .widget<YearStoryCard>(
              find.descendant(
                of: find.byType(YearExportCard),
                matching: find.byType(YearStoryCard),
              ),
            )
            .story,
        YearStory.origins,
      );
      // Removing every selection disables exporting instead of sharing a stale preview.
      await tester.tap(find.byKey(const ValueKey('year-pick-intro')));
      await tester.tap(find.byKey(const ValueKey('year-pick-origins')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('year-share-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
