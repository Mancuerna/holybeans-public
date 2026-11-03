import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/domain/gaggimate/binary.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/gaggimate_shot_widgets.dart';
import 'package:holybeans/ui/equipment/equipment_forms.dart';

import 'helpers/gaggimate_fixture.dart';

class FakeGaggimate implements GaggimateSource {
  bool closed = false;
  bool fail = false;
  @override
  String get machineAddress => 'http://gaggimate.local';
  @override
  Future<List<GaggimateHistoryEntry>> history() async {
    if (fail) throw const GaggimateException(GaggimateFailure.unavailable);
    return decodeGaggimateIndex(gaggimateIndex());
  }

  @override
  Future<GaggimateShot> shot(GaggimateHistoryEntry entry) async =>
      decodeGaggimateShot(
        gaggimateLog(),
        id: entry.id,
        machineAddress: machineAddress,
        notes: {'doseIn': '18'},
      );
  @override
  void close() => closed = true;
}

void main() {
  testWidgets('imports a shot and saves its measured fields and curve', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = connectGaggimate;
    final machine = FakeGaggimate();
    connectGaggimate = (_) => machine;
    addTearDown(() => connectGaggimate = original);
    final repo = JournalRepository(db);
    await repo.createCoffee(
      name: 'Espresso beans',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    await repo.createMethod(
      name: 'Gaggia',
      category: 'espresso',
      machine: 'gaggimate',
      machineAddress: 'gaggimate.local',
    );
    await tester.pumpWidget(
      HolyBeansApp(database: db, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brew').last);
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    final selector = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Choose a method',
    );
    await tester.scrollUntilVisible(selector, 200, scrollable: scroll);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaggia').last);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('brew-import-gaggimate'));
    await tester.scrollUntilVisible(button, 200, scrollable: scroll);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gaggimate-shot-31')));
    await tester.pumpAndSettle();
    expect(machine.closed, isTrue);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final brew = (await repo.allBrews()).single;
    expect(
      (brew.doseGrams, brew.beverageGrams, brew.timeSeconds, brew.pressureBar),
      (18.0, 36.5, 30, 9.0),
    );
    expect(
      (brew.firstDripSeconds, brew.preinfusionSeconds, brew.profileName),
      (4, null, 'Café test'),
    );
    expect((await repo.brewCurve(brew.id))!.curve.flow, everyElement(1.2));
    expect(await repo.importedGaggimateShots(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final lang in ['es', 'en']) {
    testWidgets('method connection and picker retry in $lang', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final original = connectGaggimate;
      final machine = FakeGaggimate();
      connectGaggimate = (_) => machine;
      addTearDown(() => connectGaggimate = original);
      final id = await repo.createMethod(
        name: 'Gaggia',
        category: 'espresso',
        machine: 'gaggimate',
        machineAddress: 'gaggimate.local',
      );
      final method = (await repo.allMethods()).singleWhere((m) => m.id == id);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showMethodForm(context, repo, method),
                    child: const Text('method'),
                  ),
                  TextButton(
                    onPressed: () => pickGaggimateShot(
                      context,
                      address: 'gaggimate.local',
                      imported: {},
                    ),
                    child: const Text('pick'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('method'));
      await tester.pumpAndSettle();
      final connection = find.byKey(const ValueKey('method-machine-test'));
      await tester.scrollUntilVisible(
        connection,
        180,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet).last,
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      await tester.tap(connection);
      await tester.pumpAndSettle();
      expect(find.textContaining('Café test'), findsOneWidget);
      await tester.tap(find.text(lang == 'en' ? 'Cancel' : 'Cancelar'));
      await tester.pumpAndSettle();
      machine.fail = true;
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gaggimate-error')), findsOneWidget);
      machine.fail = false;
      await tester.tap(find.text(lang == 'en' ? 'Retry' : 'Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gaggimate-shot-31')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
