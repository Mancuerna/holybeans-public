import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('label-output-test-');
    file = File(path.join(directory.path, 'preferences.json'));
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'reopening restores last model and independent paper per model',
    () async {
      final settings = LabelOutputPreferences(file);
      await settings.remember(LabelPaper.mm15x50);
      await settings.remember(LabelPaper.mm40x40);
      final reopened = LabelOutputPreferences(file);
      await reopened.load();
      expect(reopened.model, LabelPrinterModel.b1);
      expect(reopened.paperFor(LabelPrinterModel.d110), LabelPaper.mm15x50);
      expect(reopened.paperFor(LabelPrinterModel.b1), LabelPaper.mm40x40);
      expect(
        reopened.paperFor(LabelPrinterModel.b1Pro),
        LabelPrinterModel.b1Pro.defaultPaper,
      );
    },
  );

  test(
    'missing, damaged, unknown or incompatible choices use defaults',
    () async {
      final settings = LabelOutputPreferences(file);
      await settings.load();
      expect(settings.model, isNull);
      for (final data in [
        '{broken',
        '[]',
        '{"model":"future","papers":{"b1":{"widthMm":15,"lengthMm":30},"d110":false}}',
      ]) {
        await file.writeAsString(data);
        await settings.load();
        expect(settings.model, isNull);
        for (final model in LabelPrinterModel.values) {
          expect(settings.paperFor(model), model.defaultPaper);
        }
      }
    },
  );

  test('invalid paper cannot overwrite a valid preference', () async {
    final settings = LabelOutputPreferences(file);
    await settings.remember(LabelPaper.mm50x30);
    await expectLater(
      settings.remember(const LabelPaper(50, 30)),
      throwsFormatException,
    );
    final reopened = LabelOutputPreferences(file);
    await reopened.load();
    expect(reopened.model, LabelPrinterModel.b1);
    expect(reopened.paperFor(LabelPrinterModel.b1), LabelPaper.mm50x30);
  });

  test(
    'P12 tape preference survives reopening independently of Niimbot',
    () async {
      final settings = LabelOutputPreferences(file);
      await settings.remember(LabelPaper.mm12x40);
      const tape = LabelPaper(15, 50, LabelPrinterModel.marklifeP12);
      await settings.remember(tape);
      final reopened = LabelOutputPreferences(file);
      await reopened.load();
      expect(reopened.model, LabelPrinterModel.marklifeP12);
      expect(reopened.paperFor(LabelPrinterModel.marklifeP12), tape);
      expect(reopened.paperFor(LabelPrinterModel.d110), LabelPaper.mm12x40);
      await expectLater(
        settings.remember(
          const LabelPaper(12, 40, LabelPrinterModel.marklifeP12),
        ),
        throwsFormatException,
      );
    },
  );

  test('D11 retains its own paper without changing the D110 choice', () async {
    final settings = LabelOutputPreferences(file);
    await settings.remember(LabelPaper.mm15x50);
    const d11Paper = LabelPaper(12, 40, LabelPrinterModel.d11);
    await settings.remember(d11Paper);
    final reopened = LabelOutputPreferences(file);
    await reopened.load();
    expect(reopened.model, LabelPrinterModel.d11);
    expect(reopened.paperFor(LabelPrinterModel.d11), d11Paper);
    expect(reopened.paperFor(LabelPrinterModel.d110), LabelPaper.mm15x50);
  });
}
