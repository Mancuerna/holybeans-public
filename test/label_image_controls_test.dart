import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_image_options.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_graphic_controller.dart';
import 'package:holybeans/ui/labels/label_output_settings.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'image controls update options and fit narrow large text: $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final graphic = LabelGraphicController()..data = 'fixture';
        addTearDown(graphic.dispose);
        var options = const LabelImageOptions();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LabelGraphicControls(
                      graphic: graphic,
                      options: options,
                      onOptions: (next) => setState(() => options = next),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final s = await AppLocalizations.delegate.load(Locale(language));
        Future<void> choose(String key, String text) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
          await tester.tap(find.text(text).last);
          await tester.pumpAndSettle();
        }

        await choose('label-image-position', s.labelImageLeft);
        expect(options.position, LabelImagePosition.left);
        await choose('label-image-alignment', s.labelImageBelow);
        expect(options.alignment, LabelImageAlignment.end);
        await choose('label-image-mode', s.labelImagePhoto);
        expect(options.mode, LabelImageMode.photo);
        for (final key in ['label-image-size', 'label-image-contrast']) {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.tapAt(tester.getCenter(finder));
          await tester.pumpAndSettle();
        }
        expect(options.size, isNot(0.4));
        expect(options.contrast, isNot(1));
        for (final key in ['label-image-offset-x', 'label-image-offset-y']) {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.drag(finder, const Offset(60, 0));
          await tester.pumpAndSettle();
        }
        expect(options.offsetX, greaterThan(0));
        expect(options.offsetY, greaterThan(0));
        final reset = find.byKey(const ValueKey('label-image-offset-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(options.offsetX, 0);
        expect(options.offsetY, 0);
        expect(options.position, LabelImagePosition.left);
        expect(options.alignment, LabelImageAlignment.end);
        expect(options.size, isNot(0.4));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
