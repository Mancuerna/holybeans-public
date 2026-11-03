import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/domain/bookoo_pressure_protocol.dart';
import 'package:holybeans/domain/pressure_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/settings/pressure_sensor_section.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/fake_scale.dart';

void main() {
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  group('BOOKOO Espresso Monitor protocol', () {
    test('reads unsigned big-endian hundredths of a bar', () {
      expect(parseBookooPressureBar([2, 27, 0, 0, 3, 142, 85, 0, 0, 0]), 9.1);
      expect(parseBookooPressureBar([2, 27, 0, 0, 0, 1, 85, 0, 0, 0]), 0.01);
      expect(parseBookooPressureBar([2, 27, 0, 0, 0, 0, 85, 0, 0, 0]), 0);
      expect(
        parseBookooPressureBar([2, 27, 0, 0, 255, 255, 85, 0, 0, 0]),
        655.35,
      );
    });

    test('rejects incomplete frames and other messages', () {
      const packet = [2, 27, 0, 0, 3, 142, 85, 0, 0, 0];
      for (var length = 0; length < packet.length; length++) {
        expect(parseBookooPressureBar(packet.take(length).toList()), isNull);
      }
      expect(parseBookooPressureBar([...packet, 0]), isNull);
      expect(parseBookooPressureBar([3, ...packet.skip(1)]), isNull);
      expect(parseBookooPressureBar([2, 12, ...packet.skip(2)]), isNull);
      expect(parseBookooPressureBar([2, 27, 0, 0, -1, 0, 85, 0, 0, 0]), isNull);
      expect(
        parseBookooPressureBar([2, 27, 0, 0, 256, 0, 85, 0, 0, 0]),
        isNull,
      );
    });

    test('recognises the sensor by its advertised name', () {
      expect(isBookooPressureName('BOOKOO_EM-1A2B'), isTrue);
      expect(isBookooPressureName('bookoo_em'), isTrue);
      expect(isBookooPressureName('BOOKOO_SC_U'), isFalse);
      expect(isBookooPressureName('PRS-1'), isFalse);
      expect(isBookooPressureName(null), isFalse);
    });
  });

  group('pressure recording', () {
    test('keeps both sets of readings and its peak', () {
      final recording = PressureRecording()
        ..add(0, 0.2)
        ..add(50, 3)
        ..add(100, 9.1)
        ..add(250, 8.7);
      expect(recording.peakBar, 9.1);
      final curve = recording.addTo(
        ShotCurve(
          timesMs: const [0, 120, 260, 400],
          flow: const [],
          weight: const [0, 1, 2, 3],
        ),
      );
      expect(curve.timesMs, [0, 50, 100, 120, 250, 260, 400]);
      expect(curve.pressure[1], 3);
      expect(curve.pressure[2], 9.1);
      expect(curve.maxOf(CurveSeries.pressure), recording.peakBar);
      expect(curve.weight, containsAllInOrder([0, 1, 2, 3]));
    });

    test('leaves a machine curve or an empty recording alone', () {
      final machine = ShotCurve(
        timesMs: const [0, 100],
        pressure: const [1, 2],
        flow: const [],
        weight: const [0, 1],
      );
      expect((PressureRecording()..add(0, 9)).addTo(machine), same(machine));
      final scale = ShotCurve(
        timesMs: const [0, 100],
        flow: const [],
        weight: const [0, 1],
      );
      expect(PressureRecording().addTo(scale), same(scale));
      expect(PressureRecording().peakBar, isNull);
    });
  });

  test('the paired sensor is remembered in a local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'holybeans-pressure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = PairedDeviceFile(File('${directory.path}/sensor.json'));
    expect(await store.load(), isNull);
    await store.save(const FoundDevice(id: 'AA:BB', name: 'BOOKOO_EM-1'));
    final loaded = await store.load();
    expect((loaded!.id, loaded.name), ('AA:BB', 'BOOKOO_EM-1'));
    await store.file.writeAsString('{broken');
    expect(await store.load(), isNull);
    await store.save(null);
    expect(store.file.existsSync(), isFalse);
  });

  test('the BOOKOO service ignores an old Pressensor pairing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'holybeans-sensor-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = PairedDeviceFile(File('${directory.path}/sensor.json'));
    final sensor = BlePressureSensor(store);
    addTearDown(sensor.dispose);
    await store.save(const FoundDevice(id: 'AA:BB', name: 'PRS-1'));
    expect(await sensor.loadRemembered(), isNull);
    expect((await store.load())!.name, 'PRS-1');
    await sensor.saveRemembered(
      const FoundDevice(id: 'CC:DD', name: 'BOOKOO_EM-1'),
    );
    await sensor.load();
    expect(sensor.name, 'BOOKOO_EM-1');
    expect(sensor.service, '00000fff-0000-1000-8000-00805f9b34fb');
    expect(sensor.characteristic, '0000ff02-0000-1000-8000-00805f9b34fb');
  });

  testWidgets('settings find, pair, read and forget a sensor', (tester) async {
    final sensor = FakePressureSensor(
      nearby: const [FoundDevice(id: 'AA:BB', name: 'BOOKOO_EM-1')],
    );
    addTearDown(sensor.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(children: [PressureSensorSection(sensor: sensor)]),
        ),
      ),
    );
    expect(find.textContaining('never zeroes it'), findsOneWidget);
    expect(find.textContaining('BOOKOO Espresso Monitor'), findsOneWidget);
    expect(find.textContaining('Pressensor'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sensor-find')));
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    sensor.emit(6.24);
    await tester.pump();
    expect(find.text('6.2 bar'), findsOneWidget);
    expect(find.textContaining('BOOKOO_EM-1\nConnected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sensor-forget')));
    await tester.pump();
    expect(sensor.name, isNull);
    expect(find.byKey(const ValueKey('sensor-find')), findsOneWidget);
  });

  Future<(AppDatabase, JournalRepository, String, List<Coffee>)>
  espressoJournal() async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Pressure coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'Linea',
      category: 'espresso',
    );
    return (
      database,
      repository,
      methodId,
      await database.select(database.coffees).get(),
    );
  }

  Future<Finder> openForm(
    WidgetTester tester,
    AppDatabase database,
    JournalRepository repository,
    String methodId,
    List<Coffee> coffees, {
    FakeScale? scale,
    required FakePressureSensor sensor,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BrewForm(
                  repository: repository,
                  settings: BrewParameterSettings(database),
                  coffees: coffees,
                  initialMethodId: methodId,
                  scale: scale,
                  pressureSensor: sensor,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder scrollable,
    Finder target,
  ) async {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('an espresso records the pressure with the scale curve', (
    tester,
  ) async {
    final (database, repository, methodId, coffees) = await espressoJournal();
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
    final sensor = FakePressureSensor(name: 'BOOKOO_EM-1', connected: true);
    addTearDown(scale.dispose);
    addTearDown(sensor.dispose);
    final scrollable = await openForm(
      tester,
      database,
      repository,
      methodId,
      coffees,
      scale: scale,
      sensor: sensor,
    );
    final pressure = find.byKey(const ValueKey('brew-pressure'));
    await reveal(tester, scrollable, pressure);
    await tester.enterText(pressure, '7.2');
    // With a scale, the timer starts and stops on its chart.
    final timer = find.byKey(const ValueKey('chart-timer-toggle'));
    await reveal(
      tester,
      scrollable,
      find.byKey(const ValueKey('pressure-readout')),
    );
    sensor.emit(0.1);
    await tester.pump();
    expect(find.textContaining('0.1 bar'), findsOneWidget);

    await reveal(tester, scrollable, timer);
    await tester.tap(timer);
    await tester.pump();
    await tester.runAsync(() async {
      for (final (grams, bar) in [
        (0.1, 2.0),
        (10.0, 9.1),
        (25.0, 8.5),
        (38.0, 6.0),
      ]) {
        scale.emit(grams);
        sensor.emit(bar);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    });
    await reveal(tester, scrollable, timer);
    await tester.tap(timer);
    await tester.pump();
    // Readings after the timer stopped are not recorded.
    sensor.emit(12);
    await reveal(
      tester,
      scrollable,
      find.byKey(const ValueKey('pressure-readout')),
    );
    expect(find.text('Peak: 9.1 bar'), findsOneWidget);
    await reveal(tester, scrollable, pressure);
    expect(tester.widget<TextFormField>(pressure).controller!.text, '9.1');

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final brew = await database.select(database.brews).getSingle();
    expect(brew.pressureBar, 9.1);
    final saved = (await repository.brewCurve(brew.id))!;
    expect(saved.curve.weight, containsAllInOrder([0.1, 10, 25, 38]));
    expect(saved.curve.pressure, containsAllInOrder([2, 9.1, 8.5, 6]));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a filter brew keeps only the scale in its curve', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Filter coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffees = await database.select(database.coffees).get();
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
    final sensor = FakePressureSensor(name: 'BOOKOO_EM-1', connected: true);
    addTearDown(scale.dispose);
    addTearDown(sensor.dispose);
    final scrollable = await openForm(
      tester,
      database,
      repository,
      methodId,
      coffees,
      scale: scale,
      sensor: sensor,
    );
    expect(find.byKey(const ValueKey('pressure-readout')), findsNothing);
    // With a scale, the timer starts and stops on its chart.
    final timer = find.byKey(const ValueKey('chart-timer-toggle'));
    await reveal(tester, scrollable, timer);
    await tester.tap(timer);
    await tester.pump();
    await tester.runAsync(() async {
      for (final grams in [0.1, 50.0, 120.0]) {
        scale.emit(grams);
        sensor.emit(0.1);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    });
    await reveal(tester, scrollable, timer);
    await tester.tap(timer);
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final brew = await database.select(database.brews).getSingle();
    expect(brew.pressureBar, isNull);
    final saved = (await repository.brewCurve(brew.id))!;
    expect(saved.curve.weight, [0.1, 50, 120]);
    expect(saved.curve.pressure, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Stop without sensor readings preserves the typed pressure', (
    tester,
  ) async {
    final (database, repository, methodId, coffees) = await espressoJournal();
    final sensor = FakePressureSensor(name: 'BOOKOO_EM-1', connected: true);
    addTearDown(sensor.dispose);
    final scrollable = await openForm(
      tester,
      database,
      repository,
      methodId,
      coffees,
      sensor: sensor,
    );
    final pressure = find.byKey(const ValueKey('brew-pressure'));
    await reveal(tester, scrollable, pressure);
    await tester.enterText(pressure, '9');
    final timer = find.byKey(const ValueKey('extraction-timer'));
    await reveal(tester, scrollable, timer);
    await tester.tap(timer);
    await tester.pump();
    await tester.tap(timer);
    await tester.pump();
    await reveal(tester, scrollable, pressure);
    expect(tester.widget<TextFormField>(pressure).controller!.text, '9');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect((await database.select(database.brews).getSingle()).pressureBar, 9);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'Stop replaces typed pressure; a later manual edit survives saving',
    (tester) async {
      final (database, repository, methodId, coffees) = await espressoJournal();
      final sensor = FakePressureSensor(name: 'BOOKOO_EM-1', connected: true);
      addTearDown(sensor.dispose);
      final scrollable = await openForm(
        tester,
        database,
        repository,
        methodId,
        coffees,
        sensor: sensor,
      );
      final pressure = find.byKey(const ValueKey('brew-pressure'));
      await reveal(tester, scrollable, pressure);
      await tester.enterText(pressure, '9');
      final timer = find.byKey(const ValueKey('extraction-timer'));
      await reveal(tester, scrollable, timer);
      await tester.tap(timer);
      await tester.pump();
      await tester.runAsync(() async {
        sensor.emit(8.8);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.tap(timer);
      await tester.pump();
      await reveal(tester, scrollable, pressure);
      expect(tester.widget<TextFormField>(pressure).controller!.text, '8.8');
      sensor.emit(12);
      await tester.pump();
      expect(tester.widget<TextFormField>(pressure).controller!.text, '8.8');
      await tester.enterText(pressure, '9');

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final brew = await database.select(database.brews).getSingle();
      expect(brew.pressureBar, 9);
      expect(await repository.brewCurve(brew.id), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
