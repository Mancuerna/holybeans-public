import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_share_sheet.dart';
import 'package:holybeans/ui/beans/bean_share_text.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/share_image.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final bean in [false, true]) {
    for (final light in [true, false]) {
      testWidgets('transparent PNG bean=$bean light=$light ignores app theme', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final id = await repo.createCoffee(name: 'Coffee', roaster: 'Roaster');
        await repo.createBrew(
          coffeeId: id,
          methodName: 'V60',
          doseGrams: 18,
          waterGrams: 288,
        );
        final coffee = await db.select(db.coffees).getSingle();
        final brew = await db.select(db.brews).getSingle();
        final language = light ? 'es' : 'en';
        final s = lookupAppLocalizations(Locale(language));
        Uint8List? exported;
        await tester.pumpWidget(
          localizedApp(
            theme: ThemeData(
              brightness: light ? Brightness.light : Brightness.dark,
            ),
            locale: Locale(language),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    if (bean) {
                      final result =
                          await showModalBottomSheet<BeanShareResult>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => BeanShareSheet(
                              rows: [
                                BeanShareRow('name', s.beanName, 'Coffee'),
                                BeanShareRow('roaster', s.roaster, 'Roaster'),
                              ],
                            ),
                          );
                      exported = result?.image;
                    } else {
                      final result =
                          await showModalBottomSheet<ShareBrewResult>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => ShareBrewSheet(
                              coffee: coffee,
                              brew: brew,
                              components: const [],
                              configuration: light
                                  ? null
                                  : ShareConfiguration(
                                      fields: {BrewParameter.coffee},
                                      templates: [
                                        const ShareTemplate(
                                          id: 't',
                                          name: 'Template',
                                          style: ShareTemplateStyle.filter,
                                          body: '**<coffee>**\n*<dose>*',
                                        ),
                                      ],
                                      defaults: {
                                        ShareTemplateStyle.filter: 't',
                                      },
                                    ),
                              initialFields: const {
                                BrewParameter.coffee,
                                BrewParameter.dose,
                              },
                            ),
                          );
                      exported = result?.image;
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text(s.shareTransparentBackground), findsNothing);
        await tester.tap(find.text(s.shareFormatImage));
        await tester.pumpAndSettle();
        final toggle = find.byKey(
          const ValueKey('share-transparent-background'),
        );
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

        // The same capture boundary exports an opaque card by default.
        final preview = tester.widget<ShareImagePreview>(
          find.byType(ShareImagePreview),
        );
        await tester.runAsync(() async {
          final bytes = await renderShareImage(
            tester.element(toggle),
            preview.captureKey,
          );
          await _checkPixels(bytes!, transparent: false, light: light);
        });

        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final color = find.byKey(
          ValueKey(light ? 'share-light-text' : 'share-dark-text'),
        );
        await tester.ensureVisible(color);
        await tester.tap(color);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(color).selected, isTrue);

        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final opaque = tester.widget<ShareImagePreview>(
          find.byType(ShareImagePreview),
        );
        await tester.runAsync(() async {
          final bytes = await renderShareImage(
            tester.element(toggle),
            opaque.captureKey,
          );
          await _checkPixels(bytes!, transparent: false, light: light);
        });
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        // Switching formats preserves this sheet's choices.
        await tester.tap(find.text(s.shareFormatText));
        await tester.pumpAndSettle();
        expect(find.text(s.shareTransparentBackground), findsNothing);
        await tester.tap(find.text(s.shareFormatImage));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(tester.widget<ChoiceChip>(color).selected, isTrue);

        await tester.runAsync(() async {
          tester
              .widget<FilledButton>(
                find.byKey(
                  ValueKey(bean ? 'bean-share-confirm' : 'share-confirm'),
                ),
              )
              .onPressed!();
          for (var i = 0; i < 100 && exported == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          expect(exported, isNotNull);
          await _checkPixels(exported!, transparent: true, light: light);
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.shareFormatImage));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      });
    }
  }
}

Future<void> _checkPixels(
  Uint8List bytes, {
  required bool transparent,
  required bool light,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    // In the card padding, away from the rounded corners and all text.
    final padding = (30 * image.width + image.width ~/ 2) * 4;
    expect(pixels.getUint8(padding + 3), transparent ? 0 : 255);
    if (!transparent) return;
    var visible = 0;
    var clear = 0;
    for (var i = 0; i < pixels.lengthInBytes; i += 4) {
      final alpha = pixels.getUint8(i + 3);
      if (alpha == 0) clear++;
      if (alpha < 240) continue;
      visible++;
      for (var c = 0; c < 3; c++) {
        expect(pixels.getUint8(i + c), light ? 255 : 0);
      }
    }
    expect(clear, greaterThan(image.width * image.height * 0.5));
    expect(visible, greaterThan(100));
  } finally {
    image.dispose();
    codec.dispose();
  }
}
