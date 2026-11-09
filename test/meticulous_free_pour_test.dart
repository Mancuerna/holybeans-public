import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/ui_test_support.dart';

/// A synthetic record shaped like the machine's pour-over history: a bloom
/// of 50 g, a 35 s rest and two pours, sampled every 200 ms.
Map<String, Object?> _record({
  String id = 'pour-1',
  String mode = 'free_pour',
}) {
  final pours = [(0, 8000, 50.0), (43000, 58000, 130.0), (80000, 92000, 119.1)];
  var water = 0.0;
  final samples = <Map<String, Object>>[];
  for (var t = 100; t <= 180000; t += 200) {
    var weight = 0.0;
    var flow = 0.0;
    water = 0;
    for (final (start, end, grams) in pours) {
      if (t >= end) {
        water += grams;
      } else if (t > start) {
        water += grams * (t - start) / (end - start);
        flow = grams * 1000 / (end - start);
      }
    }
    weight = water;
    samples.add({'t': t, 'w': weight, 'f': flow, 'p': 0});
  }
  return {
    'schemaVersion': 4,
    'id': id,
    'brewType': 'pour_over',
    'mode': mode,
    'name': 'Free Pour',
    'startedAt': '2026-10-06T09:16:49.502000Z',
    'completedAt': '2026-10-06T09:21:20.523000Z',
    'recipe': {'profileName': 'Free Pour', 'doseG': 19.0, 'temperatureC': 93.0},
    'measurements': {
      'doseG': 19.0,
      'waterTemperatureC': 93.0,
      'waterPouredG': 299.1,
      'beverageG': 248.5,
      'retainedG': 50.6,
      'durationMs': 267958.0,
    },
    'pours': [
      for (final (index, (start, end, grams)) in pours.indexed)
        {
          'number': index + 1,
          'startTimeMs': start,
          'endTimeMs': end,
          'waterG': grams,
          'averageFlowGps': grams * 1000 / (end - start),
        },
    ],
    'samples': samples,
  };
}

void main() {
  test('a free pour record becomes the measures, pours and curve', () {
    final pour = MeticulousFreePour.fromRecord(_record());
    expect(pour.id, 'pour-1');
    expect(pour.brewedAt, DateTime.utc(2026, 10, 6, 9, 16, 49, 502).toLocal());
    expect(
      (
        pour.doseGrams,
        pour.waterGrams,
        pour.beverageGrams,
        pour.temperatureC,
        pour.timeSeconds,
      ),
      (19.0, 299.1, 248.5, 93.0, 268),
    );
    expect(pour.pours.map((pour) => pour.grams), [50, 130, 119.1]);
    expect(pour.curve!.weight.last, closeTo(299.1, 0.01));
    expect(pour.curve!.pressure, isEmpty);
    expect(
      () => MeticulousFreePour.fromRecord(_record(mode: 'profile')),
      throwsFormatException,
    );
  });

  test('free pour replaces the bloom total before allowing a manual edit', () {
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.bloom.text = '58';
    final pour = MeticulousFreePour.fromRecord(_record());
    draft.applyFreePour(pour);
    expect(draft.bloom.text, '43');
    draft.bloom.text = '45';
    draft.applyFreePour(pour);
    expect(draft.bloom.text, '45');
    draft.pours.undoFromCurve();
    expect(draft.bloom.text, '58');
  });

  test('free pour respects chosen counts and leaves manual details intact', () {
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.pours.setCount(BrewPourKind.pour, 3);
    final pour = MeticulousFreePour.fromRecord(_record());
    draft.applyFreePour(pour);
    expect((draft.pours.bloomCount, draft.pours.pourCount), (0, 3));
    expect(draft.pours.value.phases.map((p) => p.waterGrams), [50, 130, 119.1]);
    draft.pours.undoFromCurve();
    expect((draft.pours.bloomCount, draft.pours.pourCount), (null, 3));
    draft.pours.phaseDraft(BrewPourKind.pour, 1).water.text = '42';
    draft.applyFreePour(pour);
    expect(draft.pours.value.phases.single.waterGrams, 42);
  });

  test('the client reads only the latest pour over, with GET requests, and '
      'only when it is a free pour', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requests = <String>[];
    Map<String, Object?>? last = {
      'id': 'pour-1',
      'mode': 'free_pour',
      'file': '2026-10-06/09-16-49-502-a9cf.pour-over.json.zst',
    };
    server.listen((request) {
      requests.add('${request.method} ${request.uri.path}');
      final path = request.uri.path;
      final Object? body = path == '/api/v1/history/pour-over/last'
          ? last
          : path.startsWith('/api/v1/history/pour-over/files/')
          ? _record()
          : null;
      request.response
        ..statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body ?? {'status': 'error'}))
        ..close();
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = MeticulousClient('127.0.0.1:${server.port}');
      expect((await client.lastFreePour())?.waterGrams, 299.1);
      // A pour over that followed a profile is not offered.
      last = {...?last, 'mode': 'profile'};
      expect(await client.lastFreePour(), isNull);
      // Nothing poured yet, or a firmware without pour overs: 404.
      last = null;
      expect(await client.lastFreePour(), isNull);
    }, _RealHttp());
    expect(requests, [
      'GET /api/v1/history/pour-over/last',
      'GET /api/v1/history/pour-over/files/2026-10-06/09-16-49-502-a9cf.pour-over.json.zst',
      'GET /api/v1/history/pour-over/last',
      'GET /api/v1/history/pour-over/last',
    ]);
  });

  testWidgets('a filter brew imports the latest free pour from the '
      'Meticulous of another method', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final machine = _FakeMachine();
    final previous = connectMeticulous;
    connectMeticulous = (address) {
      machine.addresses.add(address);
      return machine;
    };
    addTearDown(() => connectMeticulous = previous);
    final repository = JournalRepository(database);
    await repository.createCoffee(
      name: 'Filter beans',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    await repository.createMethod(
      name: 'Meticulous',
      category: 'espresso',
      machine: 'meticulous',
      machineAddress: '192.0.2.90',
    );
    await repository.createMethod(name: 'V60', category: 'pourover');

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await settleWithWorkers(tester);
    await tester.tap(find.text('Brew').last);
    await settleWithWorkers(tester);
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> chooseMethod(String name) async {
      final selector = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Choose a method',
      );
      await tester.scrollUntilVisible(selector, -200, scrollable: scrollable);
      await settleWithWorkers(tester);
      await tester.tap(selector);
      await settleWithWorkers(tester);
      await tester.tap(find.text(name).last);
      await settleWithWorkers(tester);
    }

    await chooseMethod('Meticulous');
    expect(find.byKey(const ValueKey('brew-meticulous')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('brew-meticulous-free-pour')),
      findsNothing,
      reason: 'espresso imports shots',
    );
    await chooseMethod('V60');
    expect(find.byKey(const ValueKey('brew-meticulous')), findsNothing);
    final importButton = find.byKey(const ValueKey('brew-import-free-pour'));
    await tester.scrollUntilVisible(importButton, 200, scrollable: scrollable);
    await settleWithWorkers(tester);
    await tester.tap(importButton);
    await settleWithWorkers(tester);
    expect(machine.addresses, ['192.0.2.90']);
    expect(find.text('Already imported'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('meticulous-free-pour-pour-1')));
    await settleWithWorkers(tester);
    expect(find.text('Free pour from the Meticulous'), findsOneWidget);

    String field(String label) => tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, label))
        .controller!
        .text;
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await tester.scrollUntilVisible(dose, -200, scrollable: scrollable);
    expect(field('Dose (g)'), '19');
    expect(field('Water (g)'), '299.1');
    await tester.tap(find.text('Save').last);
    await settleWithWorkers(tester);

    final brew = await database.select(database.brews).getSingle();
    expect(
      (brew.doseGrams, brew.waterGrams, brew.beverageGrams, brew.timeSeconds),
      (19.0, 299.1, 248.5, 268),
    );
    expect(brew.temperatureC, 93);
    final pours = BrewPours.fromStorage(
      bloomCount: brew.bloomCount,
      pourCount: brew.pourCount,
      phasesJson: brew.pourPhasesJson,
    );
    expect((pours.bloomCount, pours.pourCount), (1, 2));
    expect(pours.phases.first.restSeconds, 35);
    final saved = await repository.brewCurve(brew.id);
    expect(saved?.source, ImportOperations.meticulousFreePourSource);
    expect(await repository.importedMeticulousFreePours(), {'pour-1'});
    expect(await repository.importedMeticulousShots(), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

class _FakeMachine implements MeticulousSource {
  final addresses = <String>[];

  @override
  Future<List<MeticulousShot>> recentShots({
    int limit = 50,
    bool withCurves = false,
  }) async => const [];

  @override
  Future<MeticulousShot> shot(String id) => throw UnimplementedError();

  @override
  Future<String?> rating(String id) async => null;

  @override
  Future<MeticulousFreePour?> lastFreePour() async =>
      MeticulousFreePour.fromRecord(_record());
}

class _RealHttp extends HttpOverrides {}
