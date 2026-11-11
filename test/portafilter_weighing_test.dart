import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/portafilter_weighing.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late JournalRepository repo;
  late String coffee;
  late String method;
  late Recipient portafilter;

  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(name: 'Coffee', roaster: 'Roaster');
    portafilter = await repo.saveRecipient(
      name: 'Bottomless · 18 g basket',
      emptyGrams: 515,
      isPortafilter: true,
    );
    await repo.saveRecipient(name: 'Filter jug', emptyGrams: 200);
    method = await repo.createMethod(
      name: 'Machine',
      category: 'espresso',
      defaultRecipientId: portafilter.id,
      useRecipientCatalog: true,
    );
  });

  tearDown(() async => db.close());

  Future<BrewFormModel> model({FakeScale? scale, Brew? existing}) async =>
      BrewFormModel(
        services: AppServices.forJournal(
          repo,
          parameterSettings: BrewParameterSettings(db),
          scale: scale,
        ),

        coffees: await db.select(db.coffees).get(),
        initialCoffeeId: coffee,
        initialMethodId: method,

        existing: existing,
      );

  Future<void> mount(
    WidgetTester tester,
    BrewFormModel form,
    String language,
  ) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      localizedApp(
        locale: Locale(language),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: form,
            builder: (_, _) => PortafilterWeighButton(model: form),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(form.recipient?.id, portafilter.id);
    expect(form.jugGrams, isNull);
    form.draft.dose.text = '18';
  }

  for (final language in ['es', 'en']) {
    testWidgets(
      'manual dose requires confirmation and survives history and backup ($language)',
      (tester) async {
        final form = await tester.runAsync(model);
        addTearDown(form!.dispose);
        await mount(tester, form, language);
        final s = lookupAppLocalizations(Locale(language));
        await tester.tap(find.byKey(const ValueKey('weigh-portafilter')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        expect(find.textContaining('Filter jug'), findsNothing);
        await tester.tap(find.textContaining('Bottomless').last);
        await tester.pumpAndSettle();
        final total = find.byKey(const ValueKey('portafilter-total'));
        await tester.enterText(total, '514');
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('use-portafilter-dose')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(total, '532.6');
        await tester.pump();
        expect(
          find.byKey(const ValueKey('portafilter-net-dose')),
          findsOneWidget,
        );
        expect(form.draft.dose.text, '18');
        await tester.tap(find.text(s.cancel));
        await tester.pumpAndSettle();
        expect(form.draft.dose.text, '18');
        await tester.tap(find.byKey(const ValueKey('weigh-portafilter')));
        await tester.pumpAndSettle();
        await tester.enterText(total, '532.6');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('use-portafilter-dose')));
        await tester.pumpAndSettle();
        expect(form.draft.dose.text, '17.6');
        expect(form.draft.beverage.text, isEmpty);
        await tester.runAsync(() async {
          expect(await form.save(), isNotNull);
          final brew = await db.select(db.brews).getSingle();
          expect(brew.doseGrams, 17.6);
          expect(brew.recipientIsPortafilter, isTrue);
          expect(brew.recipientGrams, 515);
          await repo.saveRecipient(
            id: portafilter.id,
            name: 'New basket',
            emptyGrams: 520,
            isPortafilter: true,
          );
          final edited = await model(existing: brew);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(edited.recipient?.emptyGrams, 515);
          expect(edited.recipient?.isPortafilter, isTrue);
          expect(edited.draft.jugTotal.text, isEmpty);
          edited.dispose();
          final backup = await JournalBackup(db).exportJson();
          await JournalBackup(db).restoreJson(backup);
          expect(
            (await db.select(db.brews).getSingle()).toJson(),
            brew.toJson(),
          );
          expect(
            (await db.select(db.recipients).get())
                .where((r) => r.isPortafilter)
                .single
                .emptyGrams,
            520,
          );
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'scale captures gross weight without starting timer, first drip or recording',
    (tester) async {
      final scale = FakeScale(name: 'Test scale', connected: true);
      addTearDown(scale.dispose);
      final form = (await tester.runAsync(() => model(scale: scale)))!;
      addTearDown(form.dispose);
      await mount(tester, form, 'en');
      await tester.tap(find.byKey(const ValueKey('weigh-portafilter')));
      await tester.pumpAndSettle();
      scale.emit(532.6, timerMs: 2000, timerRunning: true);
      scale.emitDose(532.6);
      await tester.pump();
      form.timer.toggle();
      expect(form.timer.running, isFalse);
      expect(form.draft.dose.text, '18');
      expect(form.devices.curve, isNull);
      expect(form.draft.firstDrip.text, isEmpty);
      await tester.tap(find.byKey(const ValueKey('scale-to-portafilter')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('use-portafilter-dose')));
      await tester.pumpAndSettle();
      expect(form.draft.dose.text, '17.6');
      scale.emit(532.6, timerRunning: true);
      scale.emit(532.6, timerMs: 3000, timerRunning: true);
      await tester.pump(const Duration(seconds: 2));
      expect(form.timer.running, isFalse);
      expect(form.devices.curve, isNull);
      form.timer.toggle();
      await tester.pump();
      expect(form.timer.running, isTrue);
      form.timer.stop();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('saving remembers selected portafilter per espresso method', () async {
    final other = await repo.saveRecipient(
      name: 'Other basket',
      emptyGrams: 530,
      isPortafilter: true,
    );
    final form = await model();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    form.selectRecipient(other);
    form.draft.dose.text = '19';
    expect(await form.save(), isNotNull);
    form.dispose();
    final next = await model();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(next.recipient?.id, other.id);
    final remembered = await db.select(db.brewMethods).getSingle();
    expect(remembered.vesselGrams, 530);
    final filter = await repo.createMethod(name: 'V60', category: 'pourover');
    await next.selectMethod(filter);
    expect(next.recipient, isNull);
    next.dispose();
    await expectLater(
      repo.createMethod(
        name: 'V60',
        category: 'pourover',
        useRecipientCatalog: true,
        defaultRecipientId: other.id,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('equipment creates a portafilter with basket weight', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRecipientForm(context, repo, null, true),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('recipient-name')),
      'Double spout',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipient-grams')),
      '550.5',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final rows = await db.select(db.recipients).get();
    expect(
      rows.singleWhere((r) => r.name == 'Double spout').isPortafilter,
      isTrue,
    );
  });

  test('old backups give existing recipients beverage use', () async {
    final raw = jsonDecode(
      await JournalBackup(db).exportJson(),
    ) as Map<String, dynamic>;
    raw['version'] = 35;
    final data = raw['data'] as Map<String, dynamic>;
    for (final row
        in (data['recipients'] as List).cast<Map<String, dynamic>>()) {
      row.remove('isPortafilter');
    }
    await JournalBackup(db).restoreJson(jsonEncode(raw));
    expect(
      (await db.select(db.recipients).get()).every((r) => !r.isPortafilter),
      isTrue,
    );
  });
}
