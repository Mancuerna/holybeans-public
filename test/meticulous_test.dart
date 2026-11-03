import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

/// A synthetic history entry shaped like the machine's API: a pre-infusion
/// stage, a brew stage and the piston retracting at the end.
Map<String, Object?> _entry(
  String id, {
  double time = 1790827956.5,
  bool withData = true,
}) => {
  'id': id,
  'db_key': 1,
  'time': time,
  'file': 'x.shot.json.zst',
  'name': 'Test profile',
  'data': withData
      ? [
          for (final (ms, status, pressure, weight) in [
            (50, 'Preinfusion', 2.0, 0.0),
            (4000, 'Preinfusion', 3.0, 0.4),
            (8050, 'Brew', 8.9, 2.0),
            (20050, 'Brew', 9.24, 20.0),
            (30050, 'retracting', 4.0, 36.2),
            (32050, 'retracting', 0.0, 36.54),
          ])
            {
              'shot': {
                'pressure': pressure,
                'flow': 2.0,
                'weight': weight,
                'gravimetric_flow': 1.0,
              },
              'time': ms,
              'profile_time': ms,
              'status': status,
            },
        ]
      : null,
  'profile': {
    'id': 'profile',
    'name': 'Test profile',
    'author': 'Someone',
    'temperature': 93,
    'final_weight': 36,
  },
};

void main() {
  test(
    'import without preinfusion clears a remembered or previous shot value',
    () {
      final draft = BrewDraft();
      addTearDown(draft.dispose);
      draft.preinfusion.text = '9';
      draft.dose.text = '17';
      final entry = _entry('flat');
      final data = entry['data']! as List;
      for (final sample in data.cast<Map<String, Object?>>()) {
        if (sample['status'] == 'Preinfusion') sample['status'] = 'Brew';
      }
      final shot = MeticulousShot.fromHistoryEntry(entry);
      expect(shot.preinfusionSeconds, isNull);
      draft.applyShot(shot);
      expect(draft.preinfusion.text, isEmpty);
      expect(draft.dose.text, '17');
      draft.applyShot(MeticulousShot.fromHistoryEntry(_entry('preinfusion')));
      expect(draft.preinfusion.text, '8');
      draft.applyShot(shot);
      expect(draft.preinfusion.text, isEmpty);
    },
  );

  test('a shot curve becomes time, yield, peak pressure and pre-infusion', () {
    final shot = MeticulousShot.fromHistoryEntry(_entry('a'));
    expect(shot.id, 'a');
    expect(shot.brewedAt.millisecondsSinceEpoch, 1790827956500);
    expect(shot.profileName, 'Test profile');
    expect(shot.profileAuthor, 'Someone');
    expect(shot.temperatureC, 93);
    expect(shot.targetWeightGrams, 36);
    // From the first extraction sample to the start of retracting.
    expect(shot.timeSeconds, 30);
    expect(shot.preinfusionSeconds, 8);
    expect(shot.firstDripSeconds, 4);
    expect(shot.peakPressureBar, 9.2);
    expect(shot.yieldGrams, 36.5);
    final curve = shot.curve!;
    expect(curve.timesMs.first, 0);
    expect(curve.durationMs, 32000);
    expect(curve.maxOf(CurveSeries.pressure), 9.24);
    expect(curve.weight.last, 36.54);

    final summary = MeticulousShot.fromHistoryEntry(
      _entry('b', withData: false),
    );
    expect(summary.timeSeconds, isNull);
    expect(summary.firstDripSeconds, isNull);
    expect(summary.yieldGrams, isNull);
    expect(summary.curve, isNull);
    expect(
      () => MeticulousShot.fromHistoryEntry({'name': 'no id'}),
      throwsFormatException,
    );
  });

  test('first drip ignores noise, absent weights and auxiliary samples', () {
    Map<String, Object?> sample(int ms, String status, Object? weight) => {
      'time': ms,
      'status': status,
      'shot': {'weight': weight},
    };
    final entry = _entry('threshold')
      ..['data'] = [
        sample(500, 'heating', 1),
        sample(1000, 'Preinfusion', null),
        sample(2000, 'Preinfusion', -0.1),
        sample(3000, 'Brew', 0.09),
        sample(4500, 'Brew', 0.1),
        sample(7000, 'Brew', 4),
      ];
    expect(MeticulousShot.fromHistoryEntry(entry).firstDripSeconds, 5);
    // Machine time is retained, including the second before extraction.
    entry['data'] = [sample(1000, 'Brew', 0.09), sample(3000, 'Brew', null)];
    expect(MeticulousShot.fromHistoryEntry(entry).firstDripSeconds, isNull);
    entry['data'] = [sample(1000, 'Brew', 0), sample(3000, 'retracting', 2)];
    expect(MeticulousShot.fromHistoryEntry(entry).firstDripSeconds, isNull);
  });

  test('addresses accept a bare IP, a host with port or a URL', () {
    expect(
      MeticulousClient.normalizeAddress('192.0.2.90').toString(),
      'http://192.0.2.90',
    );
    expect(
      MeticulousClient.normalizeAddress(' meticulous.local:8080 ').toString(),
      'http://meticulous.local:8080',
    );
    expect(() => MeticulousClient.normalizeAddress(''), throwsFormatException);
    expect(
      () => MeticulousClient.normalizeAddress('ftp://x'),
      throwsFormatException,
    );
  });

  test('the client only sends GET requests to history endpoints', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requests = <String>[];
    server.listen((request) {
      requests.add('${request.method} ${request.uri}');
      final path = request.uri.path;
      final Object body = path.startsWith('/api/v1/history/rating/')
          ? {'shot_id': 'a', 'rating': 'like'}
          : {
              'history': [
                _entry(
                  'a',
                  withData: request.uri.queryParameters['dump_data'] == 'true',
                ),
                if (request.uri.queryParameters['ids'] == null)
                  _entry('b', withData: false),
              ],
            };
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    // flutter_test replaces HttpClient with a fake; use the real one here.
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = MeticulousClient('127.0.0.1:${server.port}');
      final recent = await client.recentShots(limit: 5);
      expect(recent.map((shot) => shot.id), ['a', 'b']);
      expect(recent.first.timeSeconds, isNull);
      final shot = await client.shot('a');
      expect(shot.yieldGrams, 36.5);
      expect(await client.rating('a'), 'like');
    }, _RealHttp());
    expect(requests, [
      'GET /api/v1/history?max_results=5&dump_data=false',
      'GET /api/v1/history?ids=a&max_results=1&dump_data=true',
      'GET /api/v1/history/rating/a',
    ]);
  });

  test('curves round-trip as compact JSON and find the nearest sample', () {
    final curve = ShotCurve(
      timesMs: [0, 1000, 2000, 3000],
      pressure: [0, 2.04, 6.0, 9.25],
      flow: [0, 1, 2, 2],
      weight: [0, 0, 1.5, 4.444],
    );
    final copy = ShotCurve.fromJson(curve.toJson());
    expect(copy.timesMs, [0, 1000, 2000, 3000]);
    expect(copy.pressure, [0, 2.04, 6.0, 9.25]);
    expect(copy.weight.last, 4.44);
    expect(copy.indexAt(1400), 1);
    expect(copy.indexAt(1600), 2);
    expect(copy.indexAt(9999), 3);
    expect(() => ShotCurve.fromJson('{"t":[0],"p":[]}'), throwsFormatException);
  });

  test(
    'methods keep their machine; brews keep the shot curve and link',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = JournalRepository(database);
      expect(
        () => repository.createMethod(name: 'X', machine: 'toaster'),
        throwsArgumentError,
      );
      expect(
        () => repository.createMethod(
          name: 'X',
          machine: 'meticulous',
          machineAddress: 'ftp://nope',
        ),
        throwsArgumentError,
      );
      final methodId = await repository.createMethod(
        name: 'Meticulous',
        category: 'espresso',
        machine: 'meticulous',
        machineAddress: ' 192.0.2.90 ',
      );
      final method = await database.select(database.brewMethods).getSingle();
      expect(method.machine, 'meticulous');
      expect(method.machineAddress, '192.0.2.90');
      // Without a machine there is no address.
      await repository.updateMethod(
        id: methodId,
        name: 'Meticulous',
        category: 'espresso',
        machineAddress: '192.0.2.90',
      );
      expect(
        (await database.select(database.brewMethods).getSingle())
            .machineAddress,
        isNull,
      );
      await repository.updateMethod(
        id: methodId,
        name: 'Meticulous',
        category: 'espresso',
        machine: 'meticulous',
        machineAddress: '192.0.2.90',
      );

      final coffeeId = await repository.createCoffee(
        name: 'Espresso beans',
        roaster: 'Roaster',
      );
      final shot = MeticulousShot.fromHistoryEntry(_entry('a'));
      final first = await repository.createBrew(
        coffeeId: coffeeId,
        methodId: methodId,
        methodName: 'Meticulous',
        profileName: shot.profileName,
        firstDripSeconds: shot.firstDripSeconds,
      );
      await repository.attachMeticulousShot(first, shot);
      expect(await repository.importedMeticulousShots(), {'a'});
      expect((await repository.brewCurve(first))!.curve.durationMs, 32000);
      expect(
        (await database.select(database.brews).getSingle()).profileName,
        'Test profile',
      );

      // Importing the same shot into another brew moves the link.
      final second = await repository.createBrew(
        coffeeId: coffeeId,
        methodId: methodId,
        methodName: 'Meticulous',
      );
      await repository.attachMeticulousShot(second, shot);
      final records = await database.select(database.importRecords).get();
      expect(records.single.localId, second);

      // A brew given another shot no longer marks the first one, and an
      // older record left behind for the same brew does not count either.
      await database
          .into(database.importRecords)
          .insert(
            ImportRecordsCompanion.insert(
              id: 'stale',
              source: 'meticulous',
              kind: 'shot',
              externalId: 'old-shot',
              fingerprint: '0',
              localEntity: const Value('brew'),
              localId: Value(second),
              importedAtMs: 0,
            ),
          );
      expect(await repository.importedMeticulousShots(), {'a'});
      await repository.attachMeticulousShot(
        second,
        MeticulousShot(
          id: 'b',
          brewedAt: DateTime(2026, 9, 30),
          profileName: 'Other',
        ),
      );
      expect(await repository.importedMeticulousShots(), {'b'});
      await repository.attachMeticulousShot(second, shot);

      // Curves and machines survive a backup.
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await JournalBackup(target)
          .restoreJson(await JournalBackup(database).exportJson());
      expect(await JournalRepository(target).brewCurve(first), isNotNull);
      expect(
        (await JournalRepository(target).brew(first))!.firstDripSeconds,
        4,
      );
      expect(
        (await target.select(target.brewMethods).getSingle()).machine,
        'meticulous',
      );
    },
  );

  test('v14 backups with the old Meticulous address still restore', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;
    backup['version'] = 14;
    data.remove('brewCurves');
    data['preferences'] = [
      {
        'id': 1,
        'shareFieldsJson': '[]',
        'hiddenBrewFieldsJson': null,
        'rateReminderMinutes': null,
        'localeCode': 'es',
        'meticulousAddress': '192.0.2.90',
      },
    ];
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(jsonEncode(backup));
    expect(
      (await target.select(target.appPreferences).getSingle()).localeCode,
      'es',
    );
  });

  testWidgets('a zero-pressure Meticulous shot replaces remembered pressure', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final machine = _FakeMachine(zeroPressure: true);
    final previous = connectMeticulous;
    connectMeticulous = (address) => machine;
    addTearDown(() => connectMeticulous = previous);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Espresso beans',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    final methodId = await repository.createMethod(
      name: 'Meticulous',
      category: 'espresso',
      machine: 'meticulous',
      machineAddress: '192.0.2.90',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'Meticulous',
      doseGrams: 18,
      beverageGrams: 36,
      pressureBar: 4,
      brewedAt: DateTime(2026, 10, 20),
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brew').last);
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Choose a method',
    );
    await tester.scrollUntilVisible(selector, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meticulous').last);
    await tester.pumpAndSettle();

    final pressure = find.byKey(const ValueKey('brew-pressure'));
    await tester.scrollUntilVisible(pressure, 200, scrollable: scrollable);
    expect(tester.widget<TextFormField>(pressure).controller!.text, '4');
    final importButton = find.byKey(const ValueKey('brew-import-shot'));
    await tester.scrollUntilVisible(importButton, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('meticulous-shot-new1')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(pressure, 200, scrollable: scrollable);
    expect(tester.widget<TextFormField>(pressure).controller!.text, '0');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final brews = await database.select(database.brews).get();
    expect(brews, hasLength(2));
    final imported = brews.singleWhere(
      (brew) => brew.profileName == 'Test profile',
    );
    expect(imported.pressureBar, 0);
    expect(await repository.importedMeticulousShots(), {'new1'});
    expect(await repository.brewCurve(imported.id), isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a Meticulous method imports a shot into the brew form', (
    tester,
  ) async {
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
    final coffeeId = await repository.createCoffee(
      name: 'Espresso beans',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    await repository.createMethod(
      name: 'Meticulous',
      category: 'espresso',
      machine: 'meticulous',
      machineAddress: '192.0.2.90',
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brew').last);
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Choose a method',
    );
    await tester.scrollUntilVisible(selector, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meticulous').last);
    await tester.pumpAndSettle();

    final importButton = find.byKey(const ValueKey('brew-import-shot'));
    await tester.scrollUntilVisible(importButton, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(machine.addresses, ['192.0.2.90']);
    expect(machine.withCurves, isTrue);
    await tester.tap(find.byKey(const ValueKey('meticulous-shot-new1')));
    await tester.pumpAndSettle();

    final profile = find.byKey(const ValueKey('brew-profile'));
    await tester.scrollUntilVisible(profile, 200, scrollable: scrollable);
    expect(
      tester.widget<TextFormField>(profile).controller!.text,
      'Test profile',
    );
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await tester.scrollUntilVisible(dose, 200, scrollable: scrollable);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Dose (g)'),
      '18',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final brew = await database.select(database.brews).getSingle();
    expect(brew.coffeeId, coffeeId);
    expect(brew.profileName, 'Test profile');
    expect(brew.beverageGrams, 36.5);
    expect(brew.timeSeconds, 30);
    expect(brew.pressureBar, 9.2);
    expect(brew.temperatureC, 93);
    expect(brew.preinfusionSeconds, 8);
    expect(brew.firstDripSeconds, 4);
    expect(brew.doseGrams, 18);
    expect(brew.brewedAtMs, 1790800000000);
    expect(await repository.importedMeticulousShots(), {'new1'});
    expect(await repository.brewCurve(brew.id), isNotNull);

    // The details show the profile and an interactive curve.
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 2.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espresso beans').first);
    await tester.pumpAndSettle();
    final chart = find.byKey(const ValueKey('extraction-chart'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    expect(find.text('Test profile'), findsWidgets);
    final readout = find.byKey(const ValueKey('curve-readout'));
    String readoutText() => tester
        .widgetList<Text>(
          find.descendant(of: readout, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .join(' ');
    expect(find.byKey(const ValueKey('curve-duration')), findsNothing);
    expect(readoutText(), contains('max 9.2 bar'));
    final plot = find.descendant(of: chart, matching: find.byType(CustomPaint));
    final rect = tester.getRect(plot.last);
    double seconds() {
      final text = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('curve-duration')),
              matching: find.byType(Text),
            ),
          )
          .last
          .data!;
      final parts = text.split(':').map(int.parse).toList();
      return (parts[0] * 60 + parts[1]).toDouble();
    }

    await tester.tapAt(rect.centerLeft + Offset(rect.width * 0.3, 0));
    await tester.pump();
    final early = seconds();
    await tester.tapAt(rect.centerLeft + Offset(rect.width * 0.7, 0));
    await tester.pump();
    expect(early, greaterThan(0));
    expect(seconds(), allOf(greaterThan(early + 5), lessThan(32)));
    await tester.tapAt(rect.centerLeft + Offset(rect.width * 0.3, 0));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('curve-series-weight')));
    await tester.pump();
    expect(readoutText(), isNot(contains(' g')));

    // Play resumes from the cursor, pauses and resumes; at the end the
    // readout returns to the whole shot.
    final play = find.byKey(const ValueKey('curve-replay'));
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final playing = seconds();
    expect(playing, inInclusiveRange(early + 1.5, early + 2.5));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(play);
    await tester.pump(const Duration(seconds: 2));
    expect(seconds(), closeTo(playing, 0.2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(seconds(), greaterThan(playing + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('curve-duration')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

class _FakeMachine implements MeticulousSource {
  _FakeMachine({this.zeroPressure = false});

  final bool zeroPressure;
  final addresses = <String>[];
  bool? withCurves;

  MeticulousShot _shot(
    String id, {
    double time = 1790827956.5,
    bool withData = true,
  }) {
    final entry = _entry(id, time: time, withData: withData);
    final data = entry['data'];
    if (zeroPressure && data is List) {
      for (final sample in data.cast<Map<String, Object?>>()) {
        (sample['shot']! as Map<String, Object?>)['pressure'] = 0.0;
      }
    }
    return MeticulousShot.fromHistoryEntry(entry);
  }

  @override
  Future<List<MeticulousShot>> recentShots({
    int limit = 50,
    bool withCurves = false,
  }) async {
    this.withCurves = withCurves;
    return [
      for (final (id, time) in [('new2', 1790900000.0), ('new1', 1790800000.0)])
        _shot(id, time: time, withData: withCurves),
    ];
  }

  @override
  Future<MeticulousShot> shot(String id) async => _shot(id);

  @override
  Future<String?> rating(String id) async => null;

  @override
  Future<MeticulousFreePour?> lastFreePour() async => null;
}

class _RealHttp extends HttpOverrides {}
