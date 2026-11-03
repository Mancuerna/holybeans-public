import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';

void main() {
  for (final language in ['en', 'es']) {
    testWidgets('photo and charts export with separate template ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(
        name: 'Photo coffee',
        roaster: 'Roaster',
      );
      await repo.createBrew(
        coffeeId: id,
        methodName: 'V60',
        doseGrams: 18,
        beverageGrams: 270,
        tdsPercent: 1.35,
      );
      final coffee = await db.select(db.coffees).getSingle();
      final brew = await db.select(db.brews).getSingle();
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
      );
      ShareBrewResult? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ShareBrewResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ShareBrewSheet(
                      coffee: coffee,
                      brew: brew,
                      components: const [],
                      initialPhoto: photo,
                      initialFields: const {BrewParameter.coffee},
                      recording: (
                        curve: ShotCurve(
                          timesMs: [0, 1000, 2000],
                          weight: [0, 5, 10],
                          flow: [0, 5, 5],
                        ),
                        source: 'scale',
                      ),
                      configuration: ShareConfiguration(
                        fields: {BrewParameter.coffee},
                        templates: [
                          const ShareTemplate(
                            id: 't',
                            name: 'Template',
                            style: ShareTemplateStyle.filter,
                            body: 'My <coffee>\n<dose>',
                          ),
                        ],
                        defaults: {ShareTemplateStyle.filter: 't'},
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final s = lookupAppLocalizations(Locale(language));
      await tester.tap(find.text(s.shareFormatImage));
      await tester.pumpAndSettle();
      if (language == 'es') {
        await tester.tap(
          find.byKey(const ValueKey('share-transparent-background')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('share-photo-card'));
      expect(
        find.descendant(of: card, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('My Photo')),
        findsNothing,
      );
      expect(find.text('My Photo coffee\n18 g'), findsOneWidget);
      for (final key in ['share-include-curve', 'share-include-map']) {
        final option = find.byKey(ValueKey(key));
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('share-extraction-chart')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('sensory-map-chart')),
        ),
        findsOneWidget,
      );
      await tester.runAsync(
        () => precacheImage(MemoryImage(photo), tester.element(card)),
      );
      await tester.pumpAndSettle();
      final height = tester.getSize(card).height;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('share-confirm')));
        for (var attempt = 0; attempt < 100 && result == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.text, 'My Photo coffee\n18 g');
      expect(result!.rememberFields, isFalse);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(result!.image!);
        final frame = await codec.getNextFrame();
        expect(frame.image.height, closeTo(height * 3, 1));
        final pixels = (await frame.image.toByteData())!;
        final padding = (10 * frame.image.width + frame.image.width ~/ 2) * 4;
        expect(pixels.getUint8(padding + 3), language == 'es' ? 0 : 255);
        // The photo itself stays opaque inside the transparent card.
        final photoPixel =
            (100 * frame.image.width + frame.image.width ~/ 2) * 4;
        expect(pixels.getUint8(photoPixel + 3), 255);
        frame.image.dispose();
        codec.dispose();
      });
      // Removing the photo only changes this share, and the sheet can still
      // render the selected charts. Reopening restores the coffee cover.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.shareFormatImage));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-remove-photo')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Photo coffee')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
