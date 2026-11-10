import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_share_sheet.dart';
import 'package:holybeans/ui/beans/bean_share_text.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  test(
    'share rows omit missing values and distinguish personal details',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(
        name: 'Geisha',
        roaster: 'Roaster',
        initialGrams: 250,
        paidPriceCents: 1800,
        notes: 'Private note',
      );
      final coffee = await db.select(db.coffees).getSingle();
      final rows = beanShareRows(
        lookupAppLocalizations(const Locale('en')),
        coffee,
        [],
        CoffeeStock(lots: await repo.coffeeLots(id), portions: []),
      );
      final public = {
        for (final row in rows)
          if (!row.personal) row.id,
      };
      final text = beanShareText(rows, public);
      expect(text, contains('Geisha'));
      expect(text, isNot(contains('18')));
      expect(text, isNot(contains('250')));
      expect(text, isNot(contains('Private note')));
      expect(rows.map((row) => row.id), isNot(contains('rating')));
      expect(beanShareText(rows, {'notes'}), 'Notes: Private note');
    },
  );

  testWidgets('narrow sheet requires a photo for caption', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('es'),
        home: const Scaffold(
          body: BeanShareSheet(rows: [BeanShareRow('name', 'Café', 'Geisha')]),
        ),
      ),
    );
    await tester.tap(find.text('Imagen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('bean-share-photo-caption')),
    );
    await tester.tap(find.byKey(const ValueKey('bean-share-photo-caption')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('bean-share-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo action changes its label after adding and removing', (
    tester,
  ) async {
    final s = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: BeanShareSheet(
            initialPhoto: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
            ),
            rows: const [BeanShareRow('name', 'Name', 'Geisha')],
          ),
        ),
      ),
    );
    await tester.tap(find.text(s.shareFormatImage));
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('bean-share-choose-photo'));
    expect(
      find.descendant(of: choose, matching: find.text(s.changePhoto)),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('bean-share-remove-photo')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: choose, matching: find.text(s.addPhoto)),
      findsOne,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  for (final language in ['en', 'es']) {
    for (final mode in ['text', 'card', 'photo']) {
      testWidgets('bean $mode respects fields and exports ($language)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = lookupAppLocalizations(Locale(language));
        final photo = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
        );
        BeanShareResult? result;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    result = await showModalBottomSheet<BeanShareResult>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => BeanShareSheet(
                        initialPhoto: mode == 'photo' ? photo : null,
                        rows: [
                          BeanShareRow('name', s.beanName, 'Geisha'),
                          BeanShareRow('roaster', s.roaster, 'Roaster'),
                          BeanShareRow(
                            'notes',
                            s.notes,
                            'Private',
                            personal: true,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Private'), findsNothing);
        await tester.tap(find.text(s.shareFields));
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('bean-share-field-name'));
        await tester.ensureVisible(name);
        await tester.tap(name);
        await tester.pumpAndSettle();
        final notes = find.byKey(const ValueKey('bean-share-field-notes'));
        await tester.ensureVisible(notes);
        await tester.tap(notes);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(s.shareFields));
        await tester.tap(find.text(s.shareFields));
        await tester.pumpAndSettle();
        if (mode != 'text') {
          await tester.tap(find.text(s.shareFormatImage));
          await tester.pumpAndSettle();
          if (mode == 'photo') {
            await tester.tap(
              find.byKey(const ValueKey('bean-share-photo-caption')),
            );
            await tester.pumpAndSettle();
          }
          final card = find.byKey(
            ValueKey(
              mode == 'photo' ? 'share-photo-card' : 'bean-share-card-preview',
            ),
          );
          expect(
            find.descendant(of: card, matching: find.textContaining('Geisha')),
            findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.textContaining('Private')),
            mode == 'photo' ? findsNothing : findsOneWidget,
          );
          if (mode == 'photo') {
            await tester.runAsync(
              () => precacheImage(MemoryImage(photo), tester.element(card)),
            );
            await tester.pumpAndSettle();
          }
        }
        await tester.runAsync(() async {
          final button = tester.widget<FilledButton>(
            find.byKey(const ValueKey('bean-share-confirm')),
          );
          button.onPressed!();
          button.onPressed!();
          for (var i = 0; i < 100 && result == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.transfer, isFalse);
        if (mode == 'card') {
          expect(result!.text, isNull);
        } else {
          expect(result!.text, '${s.roaster}: Roaster\n${s.notes}: Private');
        }
        if (mode == 'text') {
          expect(result!.image, isNull);
        } else {
          await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(result!.image!);
            final frame = await codec.getNextFrame();
            expect(frame.image.width, greaterThan(500));
            expect(frame.image.height, greaterThan(50));
            frame.image.dispose();
            codec.dispose();
          });
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
