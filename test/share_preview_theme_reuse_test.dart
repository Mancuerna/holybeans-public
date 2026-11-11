import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('share preview reuses themes and follows appearance changes', (
    tester,
  ) async {
    final refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    final capture = GlobalKey();
    var transparent = true;
    var light = false;
    var base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
    );
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: refresh,
        builder: (_, _, _) => localizedApp(
          theme: base,
          home: Scaffold(
            body: ShareImagePreview(
              captureKey: capture,
              transparent: transparent,
              lightText: light,
              child: const SizedBox(
                width: 200,
                height: 100,
                child: Text('Preview'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ThemeData preview() => tester
        .widget<Theme>(
          find.descendant(
            of: find.byType(ShareImagePreview),
            matching: find.byType(Theme),
          ),
        )
        .data;
    Future<void> update() async {
      refresh.value++;
      await tester.pumpAndSettle();
    }

    final themes = Set<ThemeData>.identity();
    for (var i = 0; i < 100; i++) {
      await update();
      themes.add(preview());
    }
    stdout.writeln('SHARE_PREVIEW_THEMES ${themes.length}');
    expect(preview().colorScheme.onSurface, Colors.black);
    light = true;
    await update();
    expect(preview().colorScheme.onSurface, Colors.white);
    final before = preview();
    base = base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyMedium: const TextStyle(fontSize: 23),
      ),
    );
    await update();
    expect(identical(preview(), before), false);
    expect(preview().textTheme.bodyMedium!.fontSize, 23);
    transparent = false;
    await update();
    expect(preview().colorScheme, base.colorScheme);
    expect(preview().textTheme.bodyMedium!.fontSize, 23);
    light = false;
    transparent = true;
    await update();
    expect(preview().colorScheme.onSurface, Colors.black);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(themes.length, 1);
  });
}
