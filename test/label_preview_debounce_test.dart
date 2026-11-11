import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:image/image.dart' as image;

import 'helpers/ui_test_support.dart';

class _Counter {
  int requests = 0;
}

class _Layout extends LabelLayout {
  _Layout(this.counter, int value)
    : bitmap = LabelBitmap(
        1,
        Uint8List.fromList([value.isEven ? 0 : 1]),
        image.encodePng(
          image.Image(width: 1, height: 1)
            ..setPixelRgba(0, 0, value, value, value, 255),
        ),
      ),
      super('Fixture $value', LabelPaper.mm50x30);

  final _Counter counter;
  final LabelBitmap bitmap;
  Future<LabelBitmap>? _future;
  bool get requested => _future != null;

  @override
  Future<LabelBitmap> get previewBitmap {
    if (_future == null) {
      counter.requests++;
      _future = Future.value(bitmap);
    }
    return _future!;
  }
}

void main() {
  testWidgets(
    'preview coalesces edits and explicit output uses latest layout',
    (tester) async {
      final counter = _Counter();
      final current = ValueNotifier(_Layout(counter, 0));
      addTearDown(current.dispose);
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: current,
              builder: (_, layout, _) => LabelPreview(layout: layout),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(counter.requests, 1);
      counter.requests = 0;
      for (var i = 1; i <= 100; i++) {
        current.value = _Layout(counter, i);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      stdout.writeln('LABEL_PREVIEW_REQUESTS ${counter.requests}');
      expect(counter.requests, 1);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        same(current.value.bitmap.png),
      );

      // Output bypasses the preview delay and shares the newest raster future.
      current.value = _Layout(counter, 101);
      await tester.pump();
      expect(current.value.requested, isFalse);
      expect(await current.value.rasterize(), same(current.value.bitmap));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(counter.requests, 2);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        same(current.value.bitmap.png),
      );

      final cancelled = _Layout(counter, 102);
      current.value = cancelled;
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      expect(cancelled.requested, isFalse);
      expect(counter.requests, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
