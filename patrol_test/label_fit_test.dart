import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:holybeans/ui/labels/label_text.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'B1 50x30 six-line label fits with Android asset fonts',
    tags: ['android', 'label-fit'],
    ($) async {
      expect(
        await const DriveNativeClient().channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      const template = LabelTemplate(
        id: 'fit-probe',
        name: 'Cerrado',
        kind: LabelKind.coffee,
        body:
            '☕ <coffee>\n📍 <country>\n✋ <process>\n🌱 <variety>\n'
            '  <flavor_notes>\n                   🔥 <roast_date>\n\n',
      );
      final source = template.render(const {
        'coffee': 'Cerrado',
        'country': 'Brasil',
        'process': 'Natural',
        'variety': 'Acaia, Catuai',
        'flavor_notes': 'chocolate, frutos secos, miel, dolor',
        'roast_date': '12/3/2026',
      });
      for (final size in [22.0, 14.0]) {
        final text = TextPainter(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'Plex',
              fontFamilyFallback: const ['NotoEmoji'],
              fontSize: size,
              height: 1.1,
            ),
            children: [labelMarkdownSpan(source)],
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 376);
        debugPrint(
          'B1 fit: size=$size height=${text.height} '
          'lines=${text.computeLineMetrics().length} available=232',
        );
        text.dispose();
      }
      final layout = LabelLayout(source, LabelPaper.mm50x30);
      debugPrint('B1 fit: fits=${layout.fitsPaper} size=${layout.fontSize}');
      await $.pumpWidgetAndSettle(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LabelPreview(layout: layout),
              ),
            ),
          ),
        ),
      );
      await $.takeNativeScreenshot('b1-50x30-label-fit');
      expect(layout.fitsPaper, isTrue);
      expect(LabelLayout(source, LabelPaper.mm50x30).fitsPaper, isTrue);
      final bitmap = await layout.rasterize();
      expect(bitmap.pixels, contains(1));
    },
  );
}
