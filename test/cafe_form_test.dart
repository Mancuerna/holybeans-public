import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_drink_form.dart';
import 'package:holybeans/ui/cafes/cafe_picker.dart';

void main() {
  for (final (region, language, displayed, input) in [
    (const Locale('en', 'GB'), const Locale('en'), '23/10/2026', '23/10/2026'),
    (const Locale('en', 'US'), const Locale('es'), '10/23/2026', '10/23/2026'),
  ]) {
    testWidgets('cafe date and picker input follow region $region', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = region;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final drink = CafeDrink(
        id: 'drink',
        cafeId: 'cafe',
        drinkType: 'V60',
        currency: 'EUR',
        drankAtMs: DateTime(2026, 10, 23).millisecondsSinceEpoch,
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: language,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CafeDrinkForm(
            repository: CafeRepository(db),
            data: const CafeJournalData(
              [Cafe(id: 'cafe', name: 'Cafe', createdAtMs: 0, updatedAtMs: 0)],
              [],
              [],
              [],
            ),
            existing: drink,
          ),
        ),
      );
      final date = find.text(displayed);
      expect(date, findsOneWidget);
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      final picker = find.byType(DatePickerDialog);
      final material = MaterialLocalizations.of(tester.element(picker));
      await tester.tap(find.byTooltip(material.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: picker,
        matching: find.byType(TextFormField),
      );
      expect(tester.widget<TextFormField>(field).controller!.text, input);
      await tester.enterText(
        field,
        region.countryCode == 'US' ? '10/24/2026' : '24/10/2026',
      );
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.text(material.okButtonLabel),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(region.countryCode == 'US' ? '10/24/2026' : '24/10/2026'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => db.select(db.cafeDrinks).get()),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final manualCity in [null, 'My edited city']) {
    testWidgets(
      'saved cafe city takes priority or receives explicit suggestion: $manualCity',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = CafeRepository(db);
        final entries = await tester.runAsync(CafeCatalog.load);
        final venue = entries!
            .firstWhere((e) => e.venue.name == 'Hola Coffee Lagasca')
            .venue;
        await tester.runAsync(
          () => repo.save(
            CafeDrinkInput(
              cafe: CafeInput(
                name: venue.name,
                sourceKey: venue.sourceKey,
                city: manualCity,
              ),
              drinkType: 'V60',
              drankAt: DateTime(2026, 10, 23),
            ),
          ),
        );
        final before = (await tester.runAsync(repo.read))!;
        CafeInput? selected;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<CafeInput>(
                    MaterialPageRoute(builder: (_) => CafePicker(data: before)),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Hola Coffee Lagasca');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hola Coffee Lagasca').last);
        await tester.pumpAndSettle();
        expect(selected!.city, manualCity ?? 'Madrid');
        expect(selected!.id, before.cafes.single.id);
        expect((await tester.runAsync(repo.read))!.cafes, before.cafes);
      },
    );
  }

  for (final locale in ['en', 'es']) {
    testWidgets('cafe origin suggests flags and Brazil feedback in $locale', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final calls = <String>[];
      const channel = MethodChannel('holybeans/device');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CafeDrinkForm(
            repository: CafeRepository(db),
            data: const CafeJournalData([], [], [], []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = find.byKey(const ValueKey('cafe-origin'));
      await tester.ensureVisible(origin);
      await tester.enterText(origin, 'bra');
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('faaah')));
      await tester.tap(find.byKey(const ValueKey('country-option-BR')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c == 'faaah'), hasLength(1));
      expect(find.text('💀  '), findsOneWidget);
      expect(
        tester.widget<TextFormField>(origin).controller!.text,
        locale == 'es' ? 'Brasil' : 'Brazil',
      );
      await tester.enterText(origin, 'Unknown blend');
      await tester.pumpAndSettle();
      expect(find.text('💀  '), findsNothing);
      expect(
        tester.widget<TextFormField>(origin).controller!.text,
        'Unknown blend',
      );
      expect((await tester.runAsync(CafeRepository(db).read))!.drinks, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'cafe form validates and keeps a dirty draft in $locale at large text',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CafeDrinkForm(
              repository: CafeRepository(db),
              data: const CafeJournalData([], [], [], []),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find
            .descendant(
              of: find.byType(CafeDrinkForm),
              matching: find.byType(Scrollable),
            )
            .first;
        final save = find.byKey(const ValueKey('cafe-save'));
        await tester.scrollUntilVisible(save, 400, scrollable: scroll);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.byType(CafeDrinkForm), findsOneWidget);
        expect(
          find.text(
            locale == 'en' ? 'Fill in this field' : 'Completa este campo',
          ),
          findsNWidgets(2),
        );
        expect(find.byType(SnackBar), findsNothing);
        final venue = find.byKey(const ValueKey('cafe-venue'));
        await tester.scrollUntilVisible(venue, -400, scrollable: scroll);
        await tester.enterText(venue, 'My cafe');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final s = AppLocalizations.of(
          tester.element(find.byType(CafeDrinkForm)),
        )!;
        await tester.tap(find.text(s.keepEditing));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(venue).controller!.text, 'My cafe');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('catalog loads offline and supports searching', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CafePicker(data: CafeJournalData([], [], [], [])),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Madrid');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);
    expect(find.textContaining('Madrid · España'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'zzzz-no-such-cafe');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
  });
}
