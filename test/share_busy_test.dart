import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';

typedef _Renderer = Future<Uint8List?> Function(
  BuildContext context,
  GlobalKey key, {
  Uint8List? photo,
});

class _Harness {
  ShareBrewResult? result;
}

void main() {
  late AppDatabase db;
  late Coffee coffee;
  late Brew brew;
  late ShareTemplateSettings templates;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(db);
    final coffeeId = await repository.createCoffee(
      name: 'Busy coffee',
      roaster: 'R',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
      beverageGrams: 270,
      tdsPercent: 1.35,
    );
    coffee = (await repository.coffee(coffeeId))!;
    brew = (await repository.brew(brewId))!;
    templates = ShareTemplateSettings(db);
  });

  tearDown(() => db.close());

  Future<_Harness> openSheet(
    WidgetTester tester, {
    required _Renderer renderer,
  }) async {
    final harness = _Harness();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                harness.result = await showModalBottomSheet<ShareBrewResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ShareBrewSheet(
                    coffee: coffee,
                    brew: brew,
                    components: const [],
                    initialFields: const {BrewParameter.coffee},
                    initialPhoto: base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
                    ),
                    recording: (
                      curve: ShotCurve(
                        timesMs: [0, 1000],
                        weight: [0, 18],
                        flow: [0, 2],
                      ),
                      source: 'scale',
                    ),
                    templateSettings: templates,
                    configuration: ShareConfiguration(
                      fields: const {BrewParameter.coffee},
                      templates: const [
                        ShareTemplate(
                          id: 't',
                          name: 'Template',
                          style: ShareTemplateStyle.filter,
                          body: 'My <coffee>',
                        ),
                      ],
                    ),
                    imageRenderer: renderer,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
    await tester.pumpAndSettle();
    final fields = find.text(
      lookupAppLocalizations(const Locale('en')).shareFields,
    );
    await tester.ensureVisible(fields);
    await tester.pumpAndSettle();
    await tester.tap(fields);
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('capture locks every option and only renders once', (
    tester,
  ) async {
    final capture = Completer<Uint8List?>();
    var renders = 0;
    final harness = await openSheet(
      tester,
      renderer: (_, _, {photo}) {
        renders++;
        return capture.future;
      },
    );
    final transparent = find.byKey(
      const ValueKey('share-transparent-background'),
    );
    await tester.ensureVisible(transparent);
    await tester.tap(transparent);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
        .onPressed!();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
        .onPressed!();
    await tester.pump();

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
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    for (final key in ['share-manage-templates', 'share-choose-photo']) {
      expect(
        tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('share-remove-photo')))
          .onPressed,
      isNull,
    );
    for (final key in [
      'share-photo-caption',
      'share-transparent-background',
      'share-field-coffee',
      'share-include-curve',
      'share-include-map',
    ]) {
      final widget = tester.widget(find.byKey(ValueKey(key)));
      expect(
        widget is SwitchListTile
            ? widget.onChanged
            : (widget as CheckboxListTile).onChanged,
        isNull,
        reason: key,
      );
    }
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
          .onPressed,
      isNull,
    );
    for (final key in ['share-light-text', 'share-dark-text']) {
      expect(
        tester.widget<ChoiceChip>(find.byKey(ValueKey(key))).onSelected,
        isNull,
      );
    }
    expect(renders, 1);

    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('share-copy')))
          .onPressed,
      isNull,
    );

    capture.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(harness.result?.image, [1, 2, 3]);
    expect(find.text('Open'), findsOneWidget);
    expect(renders, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a failed capture restores controls and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    final harness = await openSheet(
      tester,
      renderer: (_, _, {photo}) {
        attempts++;
        if (attempts == 1) {
          return Future<Uint8List?>.error(StateError('Capture failed'));
        }
        return Future<Uint8List?>.value(Uint8List.fromList([1, 2, 3]));
      },
    );
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(harness.result, isNull);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).shareFailed),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const ValueKey('share-format')),
          )
          .onSelectionChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('share-confirm')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(harness.result?.image, [1, 2, 3]);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
