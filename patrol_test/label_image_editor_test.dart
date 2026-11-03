import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:patrol/patrol.dart';

import '../test/helpers/fake_label_printer.dart';

void main() {
  patrolTest(
    'image editor previews and saves a lateral logo without printing',
    tags: ['android', 'label-image-editor'],
    ($) async {
      expect(
        await const DriveNativeClient().channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final settings = ShareTemplateSettings(db);
      final printer = FakeLabelPrinter(model: LabelPrinterModel.b1);
      final directory = await Directory.systemTemp.createTemp('label-editor-');
      final source = img.Image(width: 200, height: 120);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      img.drawString(
        source,
        'HB',
        font: img.arial48,
        x: 65,
        y: 35,
        color: img.ColorRgb8(100, 100, 100),
      );
      final fixture = File(path.join(directory.path, 'logo.png'));
      await fixture.writeAsBytes(img.encodePng(source));
      const channel =
          'dev.flutter.pigeon.image_picker_android.ImagePickerApi.pickImages';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
        channel,
        (_) async => const StandardMessageCodec().encodeMessage([
          [fixture.path],
        ]),
      );
      final s = await AppLocalizations.delegate.load(const Locale('es'));
      Future<void> revealFinder(Finder finder) async {
        // Controls can be above a previously inspected preview. Start from a
        // known scroll position instead of searching downward past them.
        $.tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await $.pumpAndSettle();
        await $.scrollUntilVisible(finder: $(finder));
        await Scrollable.ensureVisible(
          $.tester.element(finder),
          alignment: 0.5,
        );
        await $.pumpAndSettle();
      }

      Future<void> reveal(String key) =>
          revealFinder(find.byKey(ValueKey(key)));

      Future<void> choose(String key, String value) async {
        await reveal(key);
        await $(ValueKey(key)).tap();
        await $(value).last.tap();
        await $.pumpAndSettle();
      }

      Future<LabelLayout> preview(String name) async {
        await reveal('label-preview');
        final layout = $.tester
            .widget<LabelPreview>(find.byType(LabelPreview))
            .layout;
        await layout.previewBitmap;
        await $.pumpAndSettle();
        await $.takeNativeScreenshot(name);
        return layout;
      }

      try {
        await $.pumpWidgetAndSettle(
          MaterialApp(
            locale: const Locale('es'),
            theme: ThemeData.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LabelPrintPage(
              coffee: const Coffee(
                id: 'c',
                name: 'Cerrado',
                roaster: 'Test',
                isFavorite: false,
                isDecaf: false,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
              components: const [],
              lots: const [],
              portions: const [],
              templates: const [],
              settings: settings,
              printer: printer,
            ),
          ),
        );
        await reveal('label-body');
        await $(const ValueKey('label-body')).enterText(
          '☕ **<coffee>**\n📍 Brasil\n✋ Natural\n🌱 Acaia, Catuai\nchocolate, miel\n🔥 12/3/2026',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal('label-image-pick');
        await $(const ValueKey('label-image-pick')).tap();
        await $.pumpAndSettle();
        await choose('label-image-position', s.labelImageLeft);
        await choose('label-image-alignment', s.labelImageAbove);
        await reveal('label-image-size');
        await $.tester.tapAt(
          $.tester.getCenter(find.byKey(const ValueKey('label-image-size'))),
        );
        await $.pumpAndSettle();
        final logo = await preview('label-editor-logo-left');
        expect(logo.fitsPaper, isTrue);
        expect(logo.graphicBounds.overlaps(logo.textBounds), isFalse);
        expect(logo.imageOptions.position, LabelImagePosition.left);
        expect(logo.imageOptions.size, isNot(0.4));
        await choose('label-image-mode', s.labelImagePhoto);
        await reveal('label-image-contrast');
        await $.tester.tapAt(
          $.tester.getCenter(
            find.byKey(const ValueKey('label-image-contrast')),
          ),
        );
        await $.pumpAndSettle();
        final photo = await preview('label-editor-photo-left');
        expect(photo.imageOptions.contrast, isNot(1));
        expect(
          (await photo.previewBitmap).pixels,
          isNot((await logo.previewBitmap).pixels),
        );
        await reveal('label-template-save');
        await $(const ValueKey('label-template-save')).tap();
        await $(const ValueKey('label-template-name'))
            .enterText('Editor lateral');
        await $(s.save).tap();
        await $.pumpAndSettle();
        final saved = (await settings.load()).labelTemplates.single;
        expect(saved.effectiveImageOptions, photo.imageOptions);
        expect(saved.imagePng, isNotNull);
        final templates = find.byType(DropdownButtonFormField<String>).first;
        await revealFinder(templates);
        await $(templates).tap();
        await $(s.labelDefault).last.tap();
        await $.pumpAndSettle();
        await $(templates).tap();
        await $('Editor lateral').last.tap();
        await $.pumpAndSettle();
        final restored = await preview('label-editor-restored');
        expect(restored.imageOptions, photo.imageOptions);
        expect(
          (await restored.rasterize()).pixels,
          (await photo.rasterize()).pixels,
        );
        expect(printer.jobs, 0);
      } finally {
        messenger.setMockMessageHandler(channel, null);
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        printer.dispose();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
