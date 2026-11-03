import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';

void main() {
  for (final language in ['en', 'es']) {
    testWidgets('the PNG preserves all pours and multiline notes ($language)', (
      tester,
    ) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Image coffee',
        roaster: 'Test roaster',
      );
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 288,
        rating: 8,
        notes: 'First line\nSecond line: still notes\n- - - - - - -\nLast line',
        pours: BrewPours(
          bloomCount: 2,
          pourCount: 10,
          phases: [
            const BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              waterGrams: 40,
              durationSeconds: 10,
              restSeconds: 30,
            ),
            const BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 2,
              waterGrams: 20,
              durationSeconds: 5,
              restSeconds: 15,
            ),
            for (var n = 1; n <= 10; n++)
              BrewPourPhase(
                kind: BrewPourKind.pour,
                number: n,
                waterGrams: 22.8,
                durationSeconds: 10,
              ),
          ],
        ),
      );
      final coffee = await database.select(database.coffees).getSingle();
      final brew = await database.select(database.brews).getSingle();

      ShareBrewResult? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ShareBrewResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ShareBrewSheet(
                      coffee: coffee,
                      brew: brew,
                      components: const [],
                      initialFields: const {
                        BrewParameter.coffee,
                        BrewParameter.method,
                        BrewParameter.dose,
                        BrewParameter.water,
                        BrewParameter.rating,
                        BrewParameter.bloomCount,
                        BrewParameter.pourCount,
                        BrewParameter.pourDetails,
                        BrewParameter.notes,
                      },
                    ),
                  );
                },
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      final strings = lookupAppLocalizations(Locale(language));
      await tester.tap(find.text(strings.shareFormatImage));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('brew-share-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('V60')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('18 g')),
        findsOneWidget,
      );
      for (final phase in [
        strings.bloomNumber(1),
        strings.bloomNumber(2),
        strings.pourNumber(1),
        strings.pourNumber(10),
      ]) {
        expect(
          find.descendant(of: card, matching: find.textContaining(phase)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'First line\nSecond line: still notes\n- - - - - - -\nLast line',
          ),
        ),
        findsOneWidget,
      );

      final cardHeight = tester.getSize(card).height;
      await tester.runAsync(() async {
        final confirm = tester
            .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
            .onPressed!;
        confirm();
        confirm(); // Two callbacks before the disabled button is rebuilt.
        for (var attempt = 0; attempt < 50 && result == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      final image = result!.image!;
      expect(image.length, greaterThan(1000));
      expect(image.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(image);
        final frame = await codec.getNextFrame();
        expect(frame.image.height, closeTo(cardHeight * 3, 1));
        expect(frame.image.height, greaterThan(900 * 3));
        frame.image.dispose();
        codec.dispose();
      });
      expect(result!.fields, contains(BrewParameter.rating));
      expect(tester.takeException(), isNull);
    });
  }
}
