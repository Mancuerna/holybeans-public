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

  Future<BrewFormModel> model({
    FakeScale? scale,
    Brew? existing,
    Brew? seed,
    bool repeat = false,
  }) async => BrewFormModel(
    services: AppServices.forJournal(
      repo,
      parameterSettings: BrewParameterSettings(db),
      scale: scale,
    ),

    coffees: await db.select(db.coffees).get(),
    initialCoffeeId: coffee,
    initialMethodId: method,

    existing: existing,
    seed: seed,
    repeat: repeat,
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

  for (final repeat in [true, false]) {
    testWidgets(
      '${repeat ? 'repeat uses current' : 'edit retains historical'} tare through A → B → A and save',
      (tester) async {
        final seed = (await tester.runAsync(() async {
          final original = await model();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          original.draft.dose.text = '18';
          expect(await original.save(), isNotNull);
          original.dispose();
          final brew = await db.select(db.brews).getSingle();
          await repo.saveRecipient(
            id: portafilter.id,
            name: 'Updated basket A',
            emptyGrams: 514.4,
            isPortafilter: true,
          );
          final other = await repo.saveRecipient(
            name: 'Basket B',
            emptyGrams: 520,
            isPortafilter: true,
          );
          // The repeated portafilter wins over the method's current default.
          final another = await model();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          another.selectRecipient(other);
          another.draft.dose.text = '18';
          expect(await another.save(), isNotNull);
          another.dispose();
          return brew;
        }))!;
        final form = (await tester.runAsync(
          () => model(
            existing: repeat ? null : seed,
            seed: repeat ? seed : null,
            repeat: repeat,
          ),
        ))!;
        addTearDown(form.dispose);
        await mount(tester, form, 'en');
        final tare = repeat ? 514.4 : 515.0;
        final name = repeat ? 'Updated basket A' : portafilter.name;
        expect(form.recipient?.emptyGrams, tare);
        expect(form.recipient?.name, name);
        await tester.tap(find.byKey(const ValueKey('weigh-portafilter')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('portafilter-total')),
          '532.6',
        );
        await tester.pump();
        final calculation = find.byKey(const ValueKey('portafilter-net-dose'));
        final expected = repeat
            ? '532.6 g − 514.4 g = 18.2 g'
            : '532.6 g − 515 g = 17.6 g';
        expect(tester.widget<Text>(calculation).data, expected);
        for (final selection in ['Basket B', name]) {
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining(selection).last);
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(calculation).data,
            selection == 'Basket B' ? '532.6 g − 520 g = 12.6 g' : expected,
          );
        }
        await tester.tap(find.byKey(const ValueKey('use-portafilter-dose')));
        await tester.pumpAndSettle();
        expect(form.draft.dose.text, repeat ? '18.2' : '17.6');
        await tester.runAsync(() async {
          final id = await form.save();
          expect(id, isNotNull);
          final brews = await db.select(db.brews).get();
          final saved = brews.singleWhere((b) => b.id == id!.id);
          expect(saved.recipientId, portafilter.id);
          expect(saved.recipientName, name);
          expect(saved.recipientGrams, tare);
          expect(saved.doseGrams, repeat ? 18.2 : 17.6);
          if (repeat) {
            expect(saved.id, isNot(seed.id));
            expect(
              brews.singleWhere((b) => b.id == seed.id).toJson(),
              seed.toJson(),
            );
          }
          final catalog = await db.select(db.recipients).get();
          expect(
            catalog.singleWhere((r) => r.id == portafilter.id).emptyGrams,
            514.4,
          );
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final archived in [false, true]) {
    test(
      'repeat resolves ${archived ? 'archived' : 'updated'} portafilter before saving without weighing',
      () async {
        final original = await model();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        original.draft.dose.text = '18';
        expect(await original.save(), isNotNull);
        original.dispose();
        final seed = await db.select(db.brews).getSingle();
        await repo.saveRecipient(
          id: portafilter.id,
          name: 'Updated basket',
          emptyGrams: 514.4,
          isPortafilter: true,
        );
        await repo.setRecipientArchived(portafilter.id, archived: archived);
        final form = await model(seed: seed, repeat: true);
        addTearDown(form.dispose);
        // No historical tare is exposed while the current catalog is loading.
        expect(form.recipient, isNull);
        expect(form.loadingRecipients, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(form.recipient?.emptyGrams, archived ? null : 514.4);
        final result = await form.save();
        expect(result, isNotNull);
        final brews = await db.select(db.brews).get();
        final saved = brews.singleWhere((b) => b.id == result!.id);
        expect(saved.recipientId, archived ? null : portafilter.id);
        expect(saved.recipientGrams, archived ? null : 514.4);
        expect(saved.doseGrams, 18);
        expect(
          brews.singleWhere((b) => b.id == seed.id).toJson(),
          seed.toJson(),
        );
      },
    );
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
