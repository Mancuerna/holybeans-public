import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../test/helpers/fake_niimbot_ble_platform.dart';
import 'support/smoke_support.dart';

void main() {
  for (final scenario in [
    (LabelPrinterModel.d110, 'es', 2304),
    (LabelPrinterModel.b1, 'en', 4096),
    (LabelPrinterModel.b1Pro, 'es', 4097),
    (LabelPrinterModel.b2Pro, 'en', 6912),
    (LabelPrinterModel.b2, 'es', 6913),
    (LabelPrinterModel.b21, 'es', 768),
    (LabelPrinterModel.b21, 'en', 769),
  ]) {
    final (model, language, modelId) = scenario;
    patrolTest(
      '${model.label} labels: edit, save, pair and print ($language)',
      tags: ['android', 'niimbot-labels', if (model.dpi == 300) 'niimbot-pro'],
      ($) async {
        expect(
          await const DriveNativeClient().channel.invokeMethod<String>(
            'package',
          ),
          'com.caffeinateddev.holybeans.patrol',
        );
        final db = await openTestDatabase();
        await clearTestData(db);
        final settings = ShareTemplateSettings(db);
        final directory = await Directory.systemTemp.createTemp(
          'niimbot-test-',
        );
        final platform = FakeNiimbotBlePlatform()..model = modelId;
        UniversalBle.setInstance(platform);
        final printer = NiimbotLabelPrinter(
          PairedDeviceFile(File(path.join(directory.path, 'printer.json'))),
          model: model,
        );
        final d110 = D110LabelPrinter(
          PairedDeviceFile(File(path.join(directory.path, 'd110.json'))),
        );
        const pickerChannel =
            'dev.flutter.pigeon.image_picker_android.ImagePickerApi.pickImages';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final fixture = File(path.join(directory.path, 'logo.png'));
        final logo = img.Image(width: 64, height: 32);
        img.fill(logo, color: img.ColorRgb8(255, 255, 255));
        img.fillRect(
          logo,
          x1: 0,
          y1: 0,
          x2: 31,
          y2: 31,
          color: img.ColorRgb8(0, 0, 0),
        );
        await fixture.writeAsBytes(img.encodePng(logo));
        messenger.setMockMessageHandler(
          pickerChannel,
          (_) async => const StandardMessageCodec().encodeMessage([
            [fixture.path],
          ]),
        );
        const coffee = Coffee(
          id: 'test-coffee',
          name: 'Etiopía Sidama',
          roaster: 'HolyBeans',
          isFavorite: false,
          isDecaf: false,
          createdAtMs: 0,
          updatedAtMs: 0,
        );
        const lot = CoffeeLot(
          id: 'test-lot',
          coffeeId: 'test-coffee',
          roastDate: '2026-10-20',
          createdAtMs: 0,
          updatedAtMs: 0,
        );
        const portion = FrozenPortion(
          id: 'test-portion',
          lotId: 'test-lot',
          label: 'F123',
          frozenDate: '2026-10-25',
          initialGrams: 18,
          remainingGrams: 18,
          createdAtMs: 0,
          updatedAtMs: 0,
        );
        final s = await AppLocalizations.delegate.load(Locale(language));
        try {
          await $.pumpWidgetAndSettle(
            MaterialApp(
              locale: Locale(language),
              theme: ThemeData(
                fontFamily: 'Plex',
                brightness: language == 'es'
                    ? Brightness.dark
                    : Brightness.light,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LabelPrintPage(
                            coffee: coffee,
                            components: const [],
                            lots: const [lot],
                            portions: const [portion],
                            templates: const [],
                            settings: settings,
                            printer: model != LabelPrinterModel.d110
                                ? d110
                                : printer,
                            otherPrinters: model != LabelPrinterModel.d110
                                ? [printer]
                                : const [],
                          ),
                        ),
                      ),
                      child: Text(s.labelPrint),
                    ),
                  ),
                ),
              ),
            ),
          );
          await $(s.labelPrint).tap();
          if (model != LabelPrinterModel.d110) {
            await $(const ValueKey(LabelPrinterModel.d110)).tap();
            await $('Niimbot ${model.label}').last.tap();
            await $.pumpAndSettle();
            final papers = $.tester.widget<DropdownButton<LabelPaper>>(
              find.byType(DropdownButton<LabelPaper>),
            );
            expect(
              papers.items!.every((item) => item.value!.model == model),
              isTrue,
            );
          }
          await $.scrollUntilVisible(finder: $(const ValueKey('label-body')));
          await $(const ValueKey('label-body'))
              .enterText('**<coffee>**\n<roaster>\n<roast_date>');
          if (model != LabelPrinterModel.d110) {
            await $.scrollUntilVisible(
              finder: $(const ValueKey('label-image-pick')),
            );
            await $(const ValueKey('label-image-pick')).tap();
            await $.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('label-image-remove')),
              findsOneWidget,
            );
          }
          await $.scrollUntilVisible(
            finder: $(const ValueKey('label-template-save')),
          );
          await $(const ValueKey('label-template-save')).tap();
          await $(const ValueKey('label-template-name'))
              .enterText('Sidama ${model.label}');
          await $(s.save).tap();
          await $.pumpAndSettle();
          expect(
            (await settings.load()).labelTemplates.single.name,
            'Sidama ${model.label}',
          );
          await $.scrollUntilVisible(
            finder: $(const ValueKey('label-preview')),
          );
          await $.tester.drag(
            find.byType(ListView).first,
            const Offset(0, -180),
          );
          await $.pumpAndSettle();
          await $.takeNativeScreenshot('label-preview-${model.name}-$language');
          await $.scrollUntilVisible(
            finder: $(const ValueKey('label-printer-find')),
          );
          await $(const ValueKey('label-printer-find'))
              .tap(settlePolicy: SettlePolicy.noSettle);
          await $.pump();
          // Stop the bounded scan once the simulated peripheral is visible.
          await printer.stopSearch();
          await $.pumpAndSettle();
          await $.scrollUntilVisible(finder: $(s.labelConnect));
          await $(s.labelConnect).first.tap();
          for (var n = 0; n < 100 && !printer.connected; n++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await $.pump();
          }
          expect(printer.connected, isTrue);
          await $.pumpAndSettle();
          await $.scrollUntilVisible(finder: $(const ValueKey('label-print')));
          await Scrollable.ensureVisible(
            $.tester.element(find.byKey(const ValueKey('label-print'))),
            alignment: 0.5,
          );
          await $.pumpAndSettle();
          expect(
            $.tester
                .widget<FilledButton>(find.byKey(const ValueKey('label-print')))
                .onPressed,
            isNotNull,
          );
          await $(const ValueKey('label-print'))
              .tap(settlePolicy: SettlePolicy.noSettle);
          // A 300 dpi raster has larger and more numerous BLE rows. The
          // original 15 s loop ended while Pro models were still transmitting.
          final started = DateTime.now();
          final deadline = started.add(const Duration(seconds: 60));
          while (DateTime.now().isBefore(deadline) &&
              (printer.printing || platform.commands.last.command != 0xf3)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await $.pump();
          }
          debugPrint(
            'Niimbot ${model.label}: job wait '
            '${DateTime.now().difference(started).inMilliseconds} ms; '
            '${platform.commands.length} commands, ${platform.chunks.length} BLE chunks; '
            'printing=${printer.printing}, last=${platform.commands.last.command}',
          );
          expect(printer.printing, isFalse);
          expect(
            platform.commands.where((p) => p.command == 0x01),
            hasLength(1),
          );
          expect(platform.commands.last.command, 0xf3);
          expect(platform.commands.where((p) => p.command == 0x85), isNotEmpty);
          // The result is below the buttons in a lazy ListView. Wait for the
          // job itself, then bring its feedback into the viewport to assert it.
          await $.pumpAndSettle();
          await $.scrollUntilVisible(
            finder: $(const ValueKey('label-feedback')),
          );
          expect(find.text(s.labelPrinted), findsOneWidget);
          await $.takeNativeScreenshot('label-printed-${model.name}-$language');
          final saved = (await settings.load()).labelTemplates.single;
          if (model != LabelPrinterModel.d110) {
            expect(saved.imagePng, isNotNull);
          }
          final backup = await JournalBackup(db).exportJson();
          await settings.deleteLabelTemplate(
            (await settings.load()).labelTemplates.single.id,
          );
          await JournalBackup(db).restoreJson(backup);
          expect(
            (await settings.load()).labelTemplates.single.name,
            'Sidama ${model.label}',
          );
          expect(
            (await settings.load()).labelTemplates.single.imagePng,
            saved.imagePng,
          );
          await $(find.byType(BackButton)).tap();
          await $.pumpAndSettle();
          expect(find.byType(LabelPrintPage), findsNothing);
        } finally {
          messenger.setMockMessageHandler(pickerChannel, null);
          await d110.stopSearch();
          await d110.disconnect();
          d110.dispose();
          await printer.stopSearch();
          await printer.disconnect();
          printer.dispose();
          await directory.delete(recursive: true);
          await db.close();
        }
      },
    );
  }
}
