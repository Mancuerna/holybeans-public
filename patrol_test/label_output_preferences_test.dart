import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:path/path.dart' as path;
import 'package:patrol/patrol.dart';

import '../test/helpers/fake_label_printer.dart';

void main() {
  patrolTest(
    'remembers printer and paper and separates output actions',
    tags: ['android', 'label-output-preferences'],
    ($) async {
      expect(
        await const DriveNativeClient().channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final d110 = FakeLabelPrinter();
      final b1 = FakeLabelPrinter(model: LabelPrinterModel.b1);
      final directory = await Directory.systemTemp.createTemp('label-output-');
      final file = File(path.join(directory.path, 'output.json'));
      Future<void> mount() async {
        final preferences = LabelOutputPreferences(file);
        await preferences.load();
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
              settings: ShareTemplateSettings(db),
              printer: d110,
              otherPrinters: [b1],
              outputPreferences: preferences,
            ),
          ),
        );
      }

      try {
        await mount();
        await $(const ValueKey(LabelPrinterModel.d110)).tap();
        await $('Niimbot B1').last.tap();
        await $(const ValueKey('label-paper-b1')).tap();
        await $('40 × 40 mm').last.tap();
        await $.pumpAndSettle();
        // Unmount and read a new preferences object, as on the next opening.
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await mount();
        expect(
          find.byKey(const ValueKey(LabelPrinterModel.b1)),
          findsOneWidget,
        );
        expect(
          $.tester
              .widget<DropdownButtonFormField<LabelPaper>>(
                find.byKey(const ValueKey('label-paper-b1')),
              )
              .initialValue,
          LabelPaper.mm40x40,
        );
        await $.takeNativeScreenshot('label-output-restored');
        await $.scrollUntilVisible(finder: $(const ValueKey('label-preview')));
        expect(
          $.tester.widget<LabelPreview>(find.byType(LabelPreview)).layout.paper,
          LabelPaper.mm40x40,
        );
        await $.scrollUntilVisible(finder: $(const ValueKey('label-export')));
        await $.pumpAndSettle();
        final printRect = $.tester.getRect(
          find.byKey(const ValueKey('label-print')),
        );
        final exportRect = $.tester.getRect(
          find.byKey(const ValueKey('label-export')),
        );
        expect(exportRect.top, greaterThan(printRect.bottom));
        await $.takeNativeScreenshot('label-output-actions');
        expect(d110.jobs + b1.jobs, 0);
        expect(b1.connected, isFalse);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        d110.dispose();
        b1.dispose();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
