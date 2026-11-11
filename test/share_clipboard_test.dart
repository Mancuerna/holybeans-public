import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/share_clipboard.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

class _Clipboard extends ShareClipboard {
  final texts = <String>[];
  final images = <Uint8List>[];
  Completer<void>? pending;
  bool fail = false;
  @override
  bool supportsImages = true;

  @override
  Future<void> copyText(String text) async {
    if (fail) throw StateError('Copy failed');
    texts.add(text);
    await pending?.future;
  }

  @override
  Future<void> copyImage(Uint8List png) async {
    if (fail) throw StateError('Copy failed');
    images.add(png);
    await pending?.future;
  }
}

void main() {
  late AppDatabase db;
  late Coffee coffee;
  late Brew brew;
  late _Clipboard clipboard;
  final copy = find.byKey(const ValueKey('share-copy'));
  final share = find.byKey(const ValueKey('share-confirm'));

  setUp(() async {
    db = memoryDatabase();
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(
      name: 'Clipboard coffee',
      roaster: 'Test',
    );
    final brewId = await repo.createBrew(
      coffeeId: id,
      methodName: 'V60',
      doseGrams: 18,
    );
    coffee = (await repo.coffee(id))!;
    brew = (await repo.brew(brewId))!;
    clipboard = _Clipboard();
  });
  tearDown(() => db.close());

  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    bool empty = false,
    bool template = false,
    Future<Uint8List?> Function()? render,
  }) async {
    await tester.pumpWidget(
      localizedApp(
        locale: Locale(language),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(language == 'es' ? 2 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: ShareBrewSheet(
            coffee: coffee,
            brew: brew,
            components: const [],
            initialFields: empty
                ? {}
                : {BrewParameter.coffee, BrewParameter.dose},
            clipboard: clipboard,
            imageRenderer: render == null ? null : (_, _, {photo}) => render(),
            configuration: template
                ? ShareConfiguration(
                    fields: {BrewParameter.coffee},
                    templates: const [
                      ShareTemplate(
                        id: 'test',
                        name: 'Test',
                        style: ShareTemplateStyle.filter,
                        body: '**<coffee>**\n<dose>',
                      ),
                    ],
                    defaults: {ShareTemplateStyle.filter: 'test'},
                  )
                : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in ['en', 'es']) {
    testWidgets('copies selected text and keeps the sheet open ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, language: language);
      final source = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data;
      expect(tester.getCenter(copy).dx, lessThan(tester.getCenter(share).dx));
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(clipboard.texts, [source]);
      expect(clipboard.images, isEmpty);
      expect(find.byType(ShareBrewSheet), findsOneWidget);
      expect(
        find.text(language == 'en' ? 'Text copied' : 'Texto copiado'),
        findsOneWidget,
      );
      expect(
        tester.widget<IconButton>(copy).tooltip,
        language == 'en' ? 'Copy text' : 'Copiar texto',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('copies rendered template text with its original markup', (
    tester,
  ) async {
    await open(tester, template: true);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard.texts, ['**Clipboard coffee**\n18 g']);
  });

  testWidgets(
    'image copy uses PNG capture and locks all export actions until done',
    (tester) async {
      final capture = Completer<Uint8List?>();
      var renders = 0;
      clipboard.pending = Completer<void>();
      await open(
        tester,
        render: () {
          renders++;
          return capture.future;
        },
      );
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      final callback = tester.widget<IconButton>(copy).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(tester.widget<IconButton>(copy).onPressed, isNull);
      expect(tester.widget<FilledButton>(share).onPressed, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool>>(
              find.byKey(const ValueKey('share-format')),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel'),
            )
            .onPressed,
        isNull,
      );
      expect(renders, 1);
      final png = Uint8List.fromList([137, 80, 78, 71]);
      capture.complete(png);
      await tester.pump();
      expect(clipboard.images.single, same(png));
      expect(clipboard.texts, isEmpty);
      expect(find.text('Image copied'), findsNothing);
      clipboard.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Image copied'), findsOneWidget);
      expect(tester.widget<IconButton>(copy).tooltip, 'Copy image');
      expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
      expect(find.byType(ShareBrewSheet), findsOneWidget);
    },
  );

  testWidgets('copy failures remain in the sheet and can be retried', (
    tester,
  ) async {
    clipboard.fail = true;
    await open(tester);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(find.text('Could not copy. Please try again.'), findsOneWidget);
    expect(find.text('Text copied'), findsNothing);
    clipboard.fail = false;
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(find.text('Text copied'), findsOneWidget);
    expect(find.text('Could not copy. Please try again.'), findsNothing);
  });

  testWidgets('failed image capture never changes the clipboard', (
    tester,
  ) async {
    await open(tester, render: () async => null);
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard.images, isEmpty);
    expect(find.text('Could not copy. Please try again.'), findsOneWidget);
  });

  testWidgets('empty content and unsupported image platforms disable copy', (
    tester,
  ) async {
    await open(tester, empty: true);
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(tester.widget<FilledButton>(share).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    clipboard.supportsImages = false;
    await open(tester);
    expect(tester.widget<IconButton>(copy).onPressed, isNotNull);
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
  });

  test(
    'platform service sends actual text and PNG bytes to their channels',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const imageChannel = MethodChannel('holybeans/share-clipboard');
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(imageChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(imageChannel, null);
      });
      const service = ShareClipboard();
      await service.copyText('Brew text');
      final png = Uint8List.fromList([137, 80, 78, 71]);
      await service.copyImage(png);
      expect(calls.first.method, 'Clipboard.setData');
      expect(calls.first.arguments, {'text': 'Brew text'});
      expect(calls.last.method, 'copyImage');
      expect(calls.last.arguments, png);
    },
  );
}
