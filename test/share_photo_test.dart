import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/share_clipboard.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/share_photo_overlay.dart';

class _Clipboard extends ShareClipboard {
  Uint8List? image;
  @override
  bool get supportsImages => true;
  @override
  Future<void> copyImage(Uint8List png) async => image = png;
}

void main() {
  for (final language in ['en', 'es']) {
    for (final panels in [false, true]) {
      testWidgets(
        'photo and charts export with separate template ($language, panels=$panels)',
        (tester) async {
          tester.view.physicalSize = Size(
            panels && language == 'es' ? 320 : 400,
            900,
          );
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
          final clipboard = _Clipboard();
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    panels && language == 'es' ? 1.5 : 1,
                  ),
                ),
                child: child!,
              ),
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
                          clipboard: clipboard,
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
          await tester.ensureVisible(
            find.byKey(const ValueKey('share-photo-caption')),
          );
          await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
          await tester.pumpAndSettle();
          if (panels) {
            final toggle = find.byKey(const ValueKey('share-charts-overlay'));
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('share-curve-panel')),
              findsNothing,
            );
            expect(find.byKey(const ValueKey('share-map-panel')), findsNothing);
          }
          final card = find.byKey(
            ValueKey(panels ? 'share-photo-overlay-card' : 'share-photo-card'),
          );
          await tester.runAsync(
            () => precacheImage(MemoryImage(photo), tester.element(card)),
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: card, matching: find.byType(Image)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: card,
              matching: find.textContaining('My Photo'),
            ),
            findsNothing,
          );
          expect(find.text('My Photo coffee\n18 g'), findsOneWidget);
          for (final key in ['share-include-curve', 'share-include-map']) {
            final option = find.byKey(ValueKey(key));
            await tester.ensureVisible(option);
            await tester.tap(option);
            await tester.pumpAndSettle();
            if (panels && key == 'share-include-curve') {
              expect(
                find.byKey(const ValueKey('share-curve-panel')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('share-map-panel')),
                findsNothing,
              );
            }
          }
          Offset? panelGap;
          if (panels) {
            final curve = find.byKey(const ValueKey('share-curve-panel'));
            final map = find.byKey(const ValueKey('share-map-panel'));
            final opacity = find.byKey(
              const ValueKey('share-overlay-background-opacity'),
            );
            await tester.ensureVisible(opacity);
            await tester.drag(opacity, const Offset(60, 0));
            await tester.pumpAndSettle();
            final selected = tester.widget<Slider>(opacity).value;
            expect(selected, greaterThan(0.5));
            for (final panel in [curve, map]) {
              expect(
                tester.widget<ShareOverlayPanel>(panel).backgroundOpacity,
                selected,
              );
            }
            final bounds = tester.getRect(card);
            final curveBounds = tester.getRect(curve);
            final mapBounds = tester.getRect(map);
            expect(curveBounds.bottom, lessThan(mapBounds.top));
            expect(bounds.contains(curveBounds.topLeft), isTrue);
            expect(bounds.contains(mapBounds.bottomRight), isTrue);
            expect(bounds.width / bounds.height, closeTo(4 / 3, 0.001));
            panelGap =
                Offset(
                  curveBounds.center.dx,
                  (curveBounds.bottom + mapBounds.top) / 2,
                ) -
                bounds.topLeft;
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
            await tester.tap(find.byKey(const ValueKey('share-copy')));
            for (
              var attempt = 0;
              attempt < 100 && clipboard.image == null;
              attempt++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump();
            }
          });
          await tester.pumpAndSettle();
          expect(clipboard.image, isNotNull);
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
          expect(result!.image, clipboard.image);
          await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(result!.image!);
            final frame = await codec.getNextFrame();
            expect(frame.image.height, closeTo(height * 3, 1));
            final pixels = (await frame.image.toByteData())!;
            final padding =
                (10 * frame.image.width + frame.image.width ~/ 2) * 4;
            expect(
              pixels.getUint8(padding + 3),
              !panels && language == 'es' ? 0 : 255,
            );
            if (panelGap != null) {
              final gap = panelGap;
              final gapPixel =
                  ((gap.dy * 3).floor() * frame.image.width +
                      (gap.dx * 3).floor()) *
                  4;
              // The space between panels shows the unchanged photo.
              for (var channel = 0; channel < 4; channel++) {
                expect(
                  pixels.getUint8(gapPixel + channel),
                  pixels.getUint8(channel),
                );
              }
            }
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
          await tester.ensureVisible(
            find.byKey(const ValueKey('share-photo-caption')),
          );
          await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('share-remove-photo')),
          );
          await tester.tap(find.byKey(const ValueKey('share-remove-photo')));
          await tester.pumpAndSettle();
          final reopenedCard = find.byKey(const ValueKey('share-photo-card'));
          expect(
            find.descendant(of: reopenedCard, matching: find.byType(Image)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: reopenedCard,
              matching: find.text('Photo coffee'),
            ),
            findsOneWidget,
          );
          if (panels) {
            final toggle = find.byKey(const ValueKey('share-charts-overlay'));
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('share-confirm')),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<IconButton>(find.byKey(const ValueKey('share-copy')))
                  .onPressed,
              isNull,
            );
            await tester.tap(find.text(s.shareFormatText));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('share-confirm')),
                  )
                  .onPressed,
              isNotNull,
            );
            await tester.tap(find.text(s.shareFormatImage));
            await tester.pumpAndSettle();
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('share-confirm')),
                  )
                  .onPressed,
              isNotNull,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
