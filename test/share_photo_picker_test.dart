import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/share_image.dart';

void main() {
  for (final language in ['es', 'en']) {
    for (final camera in [true, false]) {
      testWidgets('$language share photo from camera=$camera stays temporary', (
        tester,
      ) async {
        final directory = Directory.systemTemp.createTempSync('share-picker-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
        );
        final file = File('${directory.path}/photo.png')
          ..writeAsBytesSync(bytes);
        final calls = <MethodCall>[];
        var cancelled = true;
        const channel = MethodChannel('plugins.flutter.io/image_picker');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return cancelled ? null : file.path;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        Uint8List? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await pickSharePhoto(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        final s = lookupAppLocalizations(Locale(language));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text(s.takePhoto), findsOneWidget);
        expect(find.text(s.choosePhoto), findsOneWidget);
        // Dismissing the source menu must not launch a picker.
        Navigator.of(tester.element(find.text(s.takePhoto))).pop();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(result, isNull);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(camera ? s.takePhoto : s.choosePhoto));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(file.existsSync(), isTrue);
        expect(calls.single.arguments['source'], camera ? 0 : 1);
        calls.clear();
        cancelled = false;
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text(camera ? s.takePhoto : s.choosePhoto));
          for (var i = 0; i < 100 && result == null; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(calls.single.arguments['source'], camera ? 0 : 1);
        expect(result, bytes);
        expect(file.existsSync(), !camera);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
