import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/share_clipboard.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';
import 'package:holybeans/ui/core/share_photo_overlay.dart';

class _Clipboard extends ShareClipboard {
  Uint8List? image;
  @override
  bool get supportsImages => true;
  @override
  Future<void> copyImage(Uint8List png) async => image = png;
}

void main() {
  final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
  );
  late AppDatabase db;
  late Coffee coffee;
  late Brew brew;
  late _Clipboard clipboard;
  ShareBrewResult? result;
  final share = find.byKey(const ValueKey('share-confirm'));
  final copy = find.byKey(const ValueKey('share-copy'));
  final overlay = find.byKey(const ValueKey('share-photo-overlay'));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(name: 'Photo coffee', roaster: 'Test');
    await repo.createBrew(coffeeId: id, methodName: 'V60', doseGrams: 18);
    coffee = await db.select(db.coffees).getSingle();
    brew = await db.select(db.brews).getSingle();
    clipboard = _Clipboard();
    result = null;
  });
  tearDown(() => db.close());

  testWidgets('long overlays fit within landscape and portrait photos', (
    tester,
  ) async {
    for (final size in [const Size(400, 120), const Size(120, 400)]) {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.brown, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
      });
      const contentKey = ValueKey('long-overlay');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SharePhotoOverlay(
                photo: bytes,
                alignment: Alignment.bottomRight,
                widthFraction: 0.8,
                backgroundOpacity: 0.5,
                child: Column(
                  key: contentKey,
                  children: [
                    for (var i = 0; i < 50; i++) Text('Long template line $i'),
                    const SizedBox(height: 200, child: Text('Chart')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final card = find.byKey(const ValueKey('share-photo-overlay-card'));
      await tester.runAsync(
        () => precacheImage(MemoryImage(bytes), tester.element(card)),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(card);
      final content = find.byKey(contentKey);
      expect(
        bounds.width / bounds.height,
        closeTo(size.width / size.height, 0.001),
      );
      expect(bounds.contains(tester.getTopLeft(content)), isTrue);
      expect(bounds.contains(tester.getBottomRight(content)), isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    bool withPhoto = true,
    bool template = true,
    bool rememberOpacity = false,
    Future<Uint8List?> Function()? renderer,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(language == 'es' ? 2 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                final settings = rememberOpacity
                    ? ShareTemplateSettings(db)
                    : null;
                final saved = await settings?.load();
                if (!context.mounted) return;
                result = await showModalBottomSheet<ShareBrewResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ShareBrewSheet(
                    coffee: coffee,
                    brew: brew,
                    components: const [],
                    initialFields: const {
                      BrewParameter.coffee,
                      BrewParameter.dose,
                    },
                    initialPhoto: withPhoto ? photo : null,
                    clipboard: clipboard,
                    imageRenderer: renderer == null
                        ? null
                        : (_, _, {photo}) => renderer(),
                    templateSettings: settings,
                    configuration:
                        saved ??
                        (template
                            ? ShareConfiguration(
                                fields: {BrewParameter.coffee},
                                templates: const [
                                  ShareTemplate(
                                    id: 't',
                                    name: 'Template',
                                    style: ShareTemplateStyle.filter,
                                    body: '**<coffee>**\n<dose>',
                                  ),
                                ],
                                defaults: {ShareTemplateStyle.filter: 't'},
                              )
                            : null),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Open'));
    await tap(
      tester,
      find.text(lookupAppLocalizations(Locale(language)).shareFormatImage),
    );
    await tap(tester, overlay);
  }

  for (final language in ['en', 'es']) {
    testWidgets(
      'photo and text export together and copy identically ($language)',
      (tester) async {
        await open(tester, language: language, template: language == 'en');
        final s = lookupAppLocalizations(Locale(language));
        expect(find.byType(SelectableText), findsNothing);
        expect(
          find.byKey(const ValueKey('share-transparent-background')),
          findsNothing,
        );
        final card = find.byKey(const ValueKey('share-photo-overlay-card'));
        await tester.runAsync(
          () => precacheImage(MemoryImage(photo), tester.element(card)),
        );
        await tester.pumpAndSettle();
        final size = tester.getSize(card);
        expect(size.width / size.height, closeTo(4 / 3, 0.001));
        await tap(tester, find.byKey(const ValueKey('share-overlay-position')));
        await tester.tap(find.text(s.shareOverlayTopRight).last);
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('share-overlay-size')),
        );
        slider.onChanged!(0.4);
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(const ValueKey('share-dark-text')));
        final composition = tester.widget<SharePhotoOverlay>(
          find.byType(SharePhotoOverlay),
        );
        expect(composition.alignment, Alignment.topRight);
        expect(composition.widthFraction, 0.4);
        expect(
          tester
              .widget<ShareImagePreview>(find.byType(ShareImagePreview))
              .lightText,
          isFalse,
        );
        // Choices survive a round trip through text mode.
        await tester.tap(find.text(s.shareFormatText));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.shareFormatImage));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SharePhotoOverlay>(find.byType(SharePhotoOverlay))
              .alignment,
          Alignment.topRight,
        );
        await tester.runAsync(() async {
          await tester.tap(copy);
          for (var i = 0; i < 100 && clipboard.image == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(clipboard.image, isNotNull);
        await tester.runAsync(() async {
          await tester.tap(share);
          for (var i = 0; i < 100 && result == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(result?.image, clipboard.image);
        expect(result?.text, isNull);
        expect(result?.rememberFields, language != 'en');
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(result!.image!);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, closeTo(size.width * 3, 1));
          expect(image.height, closeTo(size.height * 3, 1));
          final pixels = (await image.toByteData())!;
          var textPixels = 0;
          var leftmostText = image.width;
          for (var i = 0; i < pixels.lengthInBytes; i += 4) {
            expect(pixels.getUint8(i + 3), 255);
            // The uniform coloured fixture remains behind the black lettering.
            if (pixels.getUint8(i) < 10 &&
                pixels.getUint8(i + 1) < 10 &&
                pixels.getUint8(i + 2) < 10) {
              textPixels++;
              final x = (i ~/ 4) % image.width;
              if (x < leftmostText) leftmostText = x;
            }
          }
          expect(textPixels, greaterThan(30));
          expect(leftmostText, greaterThan(image.width * 0.5));
          final photoCodec = await ui.instantiateImageCodec(photo);
          final photoImage = (await photoCodec.getNextFrame()).image;
          final photoPixels = (await photoImage.toByteData())!;
          for (var channel = 0; channel < 3; channel++) {
            expect(pixels.getUint8(channel), photoPixels.getUint8(channel));
          }
          photoImage.dispose();
          photoCodec.dispose();
          image.dispose();
          codec.dispose();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opacity updates the preview and is remembered on reopening', (
    tester,
  ) async {
    await open(tester, rememberOpacity: true);
    final opacity = find.byKey(
      const ValueKey('share-overlay-background-opacity'),
    );
    expect(tester.widget<Slider>(opacity).value, 0.5);
    await tester.ensureVisible(opacity);
    await tester.drag(opacity, const Offset(80, 0));
    await tester.pumpAndSettle();
    final selected = tester.widget<Slider>(opacity).value;
    expect(selected, greaterThan(0.5));
    expect(
      tester
          .widget<SharePhotoOverlay>(find.byType(SharePhotoOverlay))
          .backgroundOpacity,
      selected,
    );
    await tester.runAsync(() async {
      expect(
        (await ShareTemplateSettings(db).load()).overlayBackgroundOpacity,
        selected,
      );
    });
    Navigator.of(tester.element(overlay)).pop();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Open'));
    await tap(tester, find.text('Image'));
    await tap(tester, overlay);
    expect(tester.widget<Slider>(opacity).value, selected);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export fades only the panel, preserving foreground and photo', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    const foregroundKey = ValueKey('opaque-foreground');
    for (final lightText in [true, false]) {
      for (final opacity in [0.0, 0.5, 1.0]) {
        final foreground = lightText ? Colors.white : Colors.black;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ShareImagePreview(
                  captureKey: captureKey,
                  transparent: true,
                  lightText: lightText,
                  child: SharePhotoOverlay(
                    photo: photo,
                    alignment: Alignment.center,
                    widthFraction: 1,
                    backgroundOpacity: opacity,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: ColoredBox(
                          key: foregroundKey,
                          color: foreground,
                          child: const SizedBox(width: 20, height: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(photo),
            tester.element(find.byType(SharePhotoOverlay)),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final foregroundPosition = boundary.globalToLocal(
          tester.getCenter(find.byKey(foregroundKey)),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final pixels = (await image.toByteData())!;
          final x = foregroundPosition.dx.floor();
          final y = foregroundPosition.dy.floor();
          final foregroundPixel = (y * image.width + x) * 4;
          final panelPixel = (y * image.width + x - 40) * 4;
          for (var channel = 0; channel < 3; channel++) {
            expect(
              pixels.getUint8(foregroundPixel + channel),
              lightText ? 255 : 0,
            );
            final background = lightText ? 0 : 255;
            final expected =
                pixels.getUint8(channel) * (1 - opacity) + background * opacity;
            expect(pixels.getUint8(panelPixel + channel), closeTo(expected, 1));
          }
          expect(pixels.getUint8(panelPixel + 3), 255);
          image.dispose();
        });
      }
    }
  });

  testWidgets('missing or removed photo disables image export only', (
    tester,
  ) async {
    await open(tester, withPhoto: false);
    expect(tester.widget<FilledButton>(share).onPressed, isNull);
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(
      find.text(
        lookupAppLocalizations(const Locale('en')).sharePhotoOverlayHint,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('share-photo-caption')));
    expect(tester.widget<SwitchListTile>(overlay).value, isFalse);
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
    await tap(tester, overlay);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('share-photo-caption')),
          )
          .value,
      isFalse,
    );
    expect(tester.widget<FilledButton>(share).onPressed, isNull);
  });

  testWidgets('overlay controls lock during capture and recover on failure', (
    tester,
  ) async {
    final capture = Completer<Uint8List?>();
    await open(tester, renderer: () => capture.future);
    await tester.tap(share);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(overlay).onChanged, isNull);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('share-overlay-size')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('share-overlay-background-opacity')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<Alignment>>(
            find.byKey(const ValueKey('share-overlay-position')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('share-light-text')))
          .onSelected,
      isNull,
    );
    capture.complete(null);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).shareFailed),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
    await tap(tester, find.byKey(const ValueKey('share-remove-photo')));
    expect(tester.widget<FilledButton>(share).onPressed, isNull);
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
