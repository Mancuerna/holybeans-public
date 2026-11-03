import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_assistant_page.dart';
import 'package:holybeans/ui/settings/scale_section.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/fake_scale.dart';

void main() {
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('settings find, pair and forget a scale', (tester) async {
    final scale = FakeScale(
      nearby: const [FoundDevice(id: 'EA:54', name: 'BOOKOO_SC_U')],
    );
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(children: [ScaleSection(scale: scale)]),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('scale-readout')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('scale-find')));
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    scale.emit(5);
    await tester.pump();
    expect(find.text('5.0 g'), findsOneWidget);
    expect(find.text('Battery 77 %'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scale-tare')));
    expect(scale.commands, [ScaleCommand.tare]);

    await tester.tap(find.byKey(const ValueKey('scale-forget-BOOKOO_SC_U')));
    await tester.pump();
    expect(scale.name, isNull);
    expect(find.byKey(const ValueKey('scale-find')), findsOneWidget);
  });

  testWidgets('a problem is said once, in the readout of a paired scale', (
    tester,
  ) async {
    final scale = FakeScale(name: 'BOOKOO_SC_U')
      ..status = DeviceStatus.bluetoothOff;
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(children: [ScaleSection(scale: scale)]),
        ),
      ),
    );
    expect(find.textContaining('Turn Bluetooth on'), findsOneWidget);
    expect(find.byKey(const ValueKey('scale-readout')), findsOneWidget);
    // Its one fix is offered next to it.
    expect(
      find.byKey(const ValueKey('scale-bluetooth-settings')),
      findsOneWidget,
    );

    // Without a scale there is no readout, so the section says it.
    scale
      ..name = null
      ..notifyListeners();
    await tester.pump();
    expect(find.textContaining('Turn Bluetooth on'), findsOneWidget);
    expect(find.byKey(const ValueKey('scale-readout')), findsNothing);
  });

  testWidgets('a search that finds nothing says what to check', (tester) async {
    final scale = FakeScale();
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(children: [ScaleSection(scale: scale)]),
        ),
      ),
    );
    expect(find.textContaining('None found'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('scale-find')));
    await tester.pump();
    expect(find.textContaining('None found'), findsOneWidget);
  });

  testWidgets('the brew form takes weights from the scale and keeps the '
      'curve recorded while the timer runs', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Scale coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffees = await database.select(database.coffees).get();
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true)..emit(18.2);
    addTearDown(scale.dispose);

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
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> reveal(Finder target) async {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    Future<String> text(String label) async {
      final field = find.widgetWithText(TextFormField, label);
      await reveal(field);
      final value = tester.widget<TextFormField>(field).controller!.text;
      await reveal(find.byKey(const ValueKey('scale-live-chart')));
      return value;
    }

    final readout = find.byKey(const ValueKey('scale-live-chart'));
    await tester.scrollUntilVisible(readout, 200, scrollable: scrollable);
    await tester.ensureVisible(readout);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scale-readout')), findsNothing);
    expect(find.byKey(const ValueKey('scale-tare')), findsNothing);
    await reveal(find.byKey(const ValueKey('scale-to-dose')));
    await tester.tap(find.byKey(const ValueKey('scale-to-dose')));
    await tester.pump();
    expect(await text('Dose (g)'), '18.2');
    scale.emitDose(20.1);
    await tester.pump();
    expect(await text('Dose (g)'), '20.1');
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await reveal(dose);
    await tester.enterText(dose, '19');
    expect(await text('Dose (g)'), '19');
    // The existing action still copies the live weight after a saved dose.
    await reveal(find.byKey(const ValueKey('scale-to-dose')));
    await tester.tap(find.byKey(const ValueKey('scale-to-dose')));
    await tester.pump();
    expect(await text('Dose (g)'), '18.2');
    final water = find.widgetWithText(TextFormField, 'Water (g)');
    await reveal(water);
    await tester.enterText(water, '300');
    await tester.pump();

    // With the scale connected the empty chart is there before anything is
    // recorded, and starting lives on it, not next to the time.
    final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
    expect(find.byKey(const ValueKey('extraction-timer')), findsNothing);
    await reveal(toggle);
    expect(find.byKey(const ValueKey('scale-live-chart')), findsOneWidget);
    expect(find.descendant(of: toggle, matching: find.text('Start')), findsOne);
    final seconds = find.widgetWithText(TextFormField, 'Seconds');
    await reveal(seconds);
    await tester.enterText(seconds, '75');
    await reveal(toggle);
    final commandsBeforeInvalidStart = [...scale.commands];
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(seconds).controller!.text, '75');
    final durationError = lookupAppLocalizations(const Locale('en'))
        .invalidDuration;
    expect(find.text(durationError), findsOneWidget);
    expect(scale.commands, commandsBeforeInvalidStart);
    await tester.enterText(seconds, '');
    await reveal(toggle);
    // The timer tares the scale and records the weight until it stops.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text(durationError), findsNothing);
    // Starting brings the chart to the middle of the screen.
    final chart = tester.getRect(
      find.byKey(const ValueKey('scale-live-chart')),
    );
    final view = tester.getRect(scrollable);
    expect((chart.center.dy - view.center.dy).abs(), lessThan(view.height / 4));
    // The dial is reset on opening and again before taring and starting.
    expect(scale.commands, [
      ScaleCommand.resetTimer,
      ScaleCommand.resetTimer,
      ScaleCommand.tareAndStartTimer,
    ]);
    await reveal(readout);
    expect(find.byKey(const ValueKey('curve-readout')), findsNothing);
    // The curve will show the blooms: no need to mark them by hand.
    expect(find.text('Mark bloom'), findsNothing);
    await tester.runAsync(() async {
      for (final grams in [0.1, 40.0, 120.0, 250.0]) {
        scale.emit(grams);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    });
    // The curve is drawn while it records, without a replay button yet.
    await tester.pump();
    expect(find.byKey(const ValueKey('scale-live-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('curve-replay')), findsNothing);
    await reveal(toggle);
    expect(find.descendant(of: toggle, matching: find.text('Stop')), findsOne);
    await tester.tap(toggle);
    await tester.pump();
    expect(scale.commands.last, ScaleCommand.stopTimer);
    await reveal(readout);
    // The form leaves replaying to the brew details: one player only; the
    // chart offers to go on instead.
    expect(find.byKey(const ValueKey('curve-replay')), findsNothing);
    expect(find.descendant(of: toggle, matching: find.text('Start')), findsOne);
    await reveal(find.byKey(const ValueKey('filter-brew-progress')));
    expect(find.text('250 g'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('filter-brew-progress')),
        matching: find.text('1:13.7'),
      ),
      findsOneWidget,
    );
    expect(find.text('1:16.5'), findsOneWidget);
    expect(find.text('50 g'), findsOneWidget);
    expect(await text('Water (g)'), '250');
    final weightChip = find.byKey(const ValueKey('curve-series-weight'));
    final flowChip = find.byKey(const ValueKey('curve-series-flow'));
    await reveal(toggle);
    expect(
      tester.getRect(flowChip).left - tester.getRect(weightChip).right,
      closeTo(6, 0.1),
    );
    expect(tester.getRect(weightChip).top, tester.getRect(flowChip).top);
    expect(tester.getRect(weightChip).top, tester.getRect(toggle).top);
    expect(tester.getSize(weightChip).height, tester.getSize(toggle).height);

    scale.lose();
    await tester.pump();
    await reveal(find.byKey(const ValueKey('scale-connect')));
    expect(find.byKey(const ValueKey('scale-readout')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scale-connect')));
    await tester.pump();
    expect(find.byKey(const ValueKey('scale-readout')), findsNothing);

    scale.emit(212);
    await tester.pump();
    await reveal(find.byKey(const ValueKey('scale-to-beverage')));
    await tester.tap(find.byKey(const ValueKey('scale-to-beverage')));
    await tester.pump();
    expect(await text('Beverage weight (g)'), '212');

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final brew = await database.select(database.brews).getSingle();
    final saved = (await repository.brewCurve(brew.id))!;
    expect(brew.waterGrams, 250);
    expect(saved.source, 'scale');
    expect(saved.curve.weight, [0.1, 40, 120, 250]);
    expect(saved.curve.pressure, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('the pour assistant follows the scale', (tester) async {
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true)..emit(380);
    addTearDown(scale.dispose);
    final clock = _HandStopwatch();
    PourAssistantResult? result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PourAssistantPage(
                  plan: PourPlan.standard(15),
                  stopwatch: () => clock,
                  scale: scale,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('pour-start'));
    await tester.scrollUntilVisible(
      start,
      200,
      scrollable: find
          .descendant(
            of: find.byType(PourAssistantPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('the scale zeroes'), findsOneWidget);
    await tester.tap(start);
    await tester.pump();
    expect(scale.commands, [ScaleCommand.tareAndStartTimer]);

    // The old weight before the tare shows is not recorded.
    scale.emit(380);
    clock.elapsed = const Duration(milliseconds: 300);
    scale.emit(0);
    clock.elapsed = const Duration(seconds: 2);
    scale.emit(20);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('On the scale: 20 g, 10 g to go'), findsOneWidget);

    clock.elapsed = const Duration(seconds: 5);
    scale.emit(34);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('On the scale: 34 g, 4 g over'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pour-pause')));
    await tester.pump();
    expect(scale.commands.last, ScaleCommand.stopTimer);
    await tester.tap(find.byKey(const ValueKey('pour-pause')));
    await tester.pump();
    expect(scale.commands.last, ScaleCommand.startTimer);

    clock.elapsed = const Duration(seconds: 8);
    scale.emit(31);
    await tester.tap(find.byKey(const ValueKey('pour-finish')));
    await tester.pumpAndSettle();
    expect(result!.curve!.weight, [0, 20, 34, 31]);
    expect(result!.pouredGrams, 34);
  });

  testWidgets('paired devices connect when the app opens and comes back', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final scale = FakeScale(name: 'BOOKOO_SC_U');
    final sensor = FakePressureSensor(name: 'BOOKOO_EM-1');
    addTearDown(scale.dispose);
    addTearDown(sensor.dispose);
    await tester.pumpWidget(
      HolyBeansApp(
        database: database,
        initialLocale: const Locale('en'),
        scale: scale,
        pressureSensor: sensor,
      ),
    );
    await tester.pumpAndSettle();
    expect((scale.connected, sensor.connected), (true, true));
    // Switched off while the app is away.
    scale.lose();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(scale.connected, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('an espresso waits for its first drip and the chart can stop '
      'it', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Shot coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'Linea',
      category: 'espresso',
    );
    final coffees = await database.select(database.coffees).get();
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true)..emit(0);
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: BrewForm(
            repository: repository,
            settings: BrewParameterSettings(database),
            coffees: coffees,
            initialMethodId: methodId,
            scale: scale,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    final wait = find.byKey(const ValueKey('scale-wait-drip'));
    await tester.scrollUntilVisible(wait, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(wait);
    await tester.pump();
    expect(scale.commands, [ScaleCommand.resetTimer, ScaleCommand.tare]);
    expect(find.text('Waiting for the first drop…'), findsOneWidget);
    await tester.runAsync(() async {
      for (final grams in [0.0, 0.3, 0.5, 2.0, 6.0, 12.0, 18.0, 24.0]) {
        scale.emit(grams);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    });
    await tester.pump();
    expect(scale.commands.last, ScaleCommand.startTimer);
    expect(find.text('Recording the weight'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
    await tester.scrollUntilVisible(toggle, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(scale.commands.last, ScaleCommand.stopTimer);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('scale-readout')),
      -200,
      scrollable: scrollable,
    );
    expect(find.textContaining('Weight curve recorded'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// A stopwatch the test moves by setting [elapsed].
class _HandStopwatch implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
  bool _running = false;

  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() => elapsed = Duration.zero;
  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get frequency => 1000000;
}
