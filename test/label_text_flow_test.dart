import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:holybeans/ui/labels/label_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('Plex', 'assets/fonts/IBMPlexSans-Regular.ttf'),
      ('NotoEmoji', 'assets/fonts/NotoEmoji.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  Future<ui.Image> logo({int width = 100, int height = 100}) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.black,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    picture.dispose();
    addTearDown(result.dispose);
    return result;
  }

  test(
    'substituted adjacent dates and weight share full width below logo',
    () async {
      const template = LabelTemplate(
        id: 'flow',
        name: 'Flow',
        kind: LabelKind.frozen,
        body:
            '**<coffee>**\n<country>\n<process>\n<variety>\n'
            '<flavor_notes>\n\n🔥 <roast_date> ❄️ <freeze_date> ⚖️ <portion_weight>',
      );
      final text = template.render({
        'coffee': 'Cerrado',
        'country': 'Brasil',
        'process': 'Natural',
        'variety': 'Acaia, Catuai',
        'flavor_notes': 'chocolate, frutos secos, miel',
        'roast_date': '12/3/2026',
        'freeze_date': '23/11',
        'portion_weight': '20 g',
      });
      final graphic = await logo();
      for (final model in [LabelPrinterModel.b1, LabelPrinterModel.b1Pro]) {
        for (final side in [
          LabelImagePosition.left,
          LabelImagePosition.right,
        ]) {
          final layout = LabelLayout(
            text,
            model.defaultPaper,
            graphic: graphic,
            imageOptions: LabelImageOptions(
              position: side,
              alignment: LabelImageAlignment.start,
              size: 0.35,
            ),
          );
          expect(layout.fitsPaper, isTrue);
          final footer = layout.textLines
              .where((line) => line.span.toPlainText().contains('12/3/2026'))
              .single;
          expect(footer.span.toPlainText(), '🔥 12/3/2026 ❄️ 23/11 ⚖️ 20 g');
          expect(footer.bounds.width, layout.contentBounds.width);
          expect(
            footer.bounds.top,
            greaterThanOrEqualTo(layout.graphicBounds.bottom + 4),
          );
          for (final line in layout.textLines) {
            expect(
              line.bounds.overlaps(layout.graphicBounds.inflate(3.99)),
              isFalse,
            );
          }
          final bitmap = await layout.rasterize();
          expect(await layout.previewBitmap, same(bitmap));
          expect(
            (await layout.rasterize(upsideDown: true)).pixels,
            bitmap.pixels.reversed.toList(),
          );
        }
      }
    },
  );

  test(
    'flow preserves explicit empty lines, literal values and styled emoji',
    () async {
      const text = '**Café 👩🏽‍🌾**\n\nBrasil\n❄️ 23/11\n⚖️ 20 g\n';
      final layout = LabelLayout(
        text,
        LabelPaper.mm50x30,
        graphic: await logo(width: 200, height: 50),
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.right,
          alignment: LabelImageAlignment.start,
          size: 0.3,
        ),
      );
      expect(layout.fitsPaper, isTrue);
      expect(
        layout.textLines.map((line) => line.span.toPlainText()).join('\n'),
        labelMarkdownSpan(text).toPlainText(),
      );
      final first = layout.textLines.first.span;
      final styles = <TextStyle>[];
      void collect(TextSpan span, TextStyle inherited) {
        final style = inherited.merge(span.style);
        if (span.text?.isNotEmpty ?? false) styles.add(style);
        for (final child in span.children ?? <InlineSpan>[]) {
          collect(child as TextSpan, style);
        }
      }

      collect(first, const TextStyle());
      expect(
        styles.any((style) => style.fontWeight == FontWeight.w700),
        isTrue,
      );
      expect(styles.any((style) => style.fontFamily == 'NotoEmoji'), isTrue);
      expect((await layout.rasterize()).pixels, contains(1));
    },
  );

  test(
    'all image alignments and profiles avoid overlap and reclaim free rows',
    () async {
      final graphic = await logo(width: 200, height: 60);
      for (final model in LabelPrinterModel.values) {
        for (final side in [
          LabelImagePosition.left,
          LabelImagePosition.right,
        ]) {
          for (final alignment in LabelImageAlignment.values) {
            final layout = LabelLayout(
              'Coffee\nBrasil\n20 g',
              model.defaultPaper,
              graphic: graphic,
              imageOptions: LabelImageOptions(
                position: side,
                alignment: alignment,
              ),
            );
            expect(layout.fitsPaper, isTrue);
            for (final line in layout.textLines) {
              expect(
                line.bounds.overlaps(layout.graphicBounds.inflate(3.99)),
                isFalse,
              );
              expect(
                layout.contentBounds.contains(
                  line.bounds.bottomRight - const Offset(.01, .01),
                ),
                isTrue,
              );
            }
            if (alignment == LabelImageAlignment.end) {
              expect(
                layout.textLines.first.bounds.width,
                layout.contentBounds.width,
              );
            }
          }
        }
      }
    },
  );

  test(
    'long soft-wrapped content is preserved and excess height blocks output',
    () async {
      final graphic = await logo(width: 150);
      const text =
          'Chocolate, frutos secos, miel, cítricos y caramelo. '
          '👩🏽‍🌾 Café con notas florales, cacao y fruta madura.';
      final layout = LabelLayout(
        text,
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.right,
          alignment: LabelImageAlignment.start,
          size: 0.35,
        ),
      );
      expect(layout.fitsPaper, isTrue);
      expect(
        layout.textLines.map((line) => line.span.toPlainText()).join(),
        text,
      );
      expect(
        layout.textLines.any(
          (line) => line.bounds.width == layout.contentBounds.width,
        ),
        isTrue,
      );
      final overflow = LabelLayout(
        List.filled(60, text).join('\n'),
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.left,
        ),
      );
      expect(overflow.fitsPaper, isFalse);
      expect(overflow.rasterize(), throwsStateError);
    },
  );
}
