import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/flow_guide_page.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_page.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_reference_page.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';
import 'package:holybeans/ui/core/app_theme.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

ShotCurve reference() => ShotCurve(
  timesMs: [for (var ms = 0; ms <= 4000; ms += 500) ms],
  weight: [for (var ms = 0; ms <= 4000; ms += 500) ms / 500],
  flow: [],
);

Widget app(Widget home, {String language = 'en', double textScale = 1}) =>
    localizedApp(
      locale: Locale(language),
      theme: language == 'es' ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

void main() {
  for (final language in ['en', 'es']) {
    testWidgets(
      'scale-only guidance, stale readings, disconnect and reset ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scale = FakeScale(name: 'BOOKOO', connected: true);
        final watch = ManualStopwatch();
        var now = DateTime(2026);
        final session = BrewScaleSession(
          scale,
          stopwatch: watch,
          clock: () => now,
        );
        final minutes = TextEditingController();
        final seconds = TextEditingController();
        final timer = BrewTimer(
          minutes: minutes,
          seconds: seconds,
          onStart: session.timerStarted,
          onStop: session.timerStopped,
          onReset: session.timerReset,
        );
        session.requestStop = (_) => timer.stop();
        final guide = FlowGuide.fromCurve(reference())!;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => FlowGuidePage(
                        guide: guide,
                        title: 'Reference',
                        timer: timer,
                        session: session,
                        targetWeightGrams: 10,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            language: language,
            textScale: language == 'es' ? 2 : 1.3,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('flow-guide-toggle'));
        final weight = find.byKey(const ValueKey('flow-guide-weight'));
        final weightDifference = find.byKey(
          const ValueKey('flow-guide-weight-difference'),
        );
        String weightText() => tester.widget<Text>(weight).data!;
        expect(weightText(), contains(language == 'en' ? '10.0' : '10,0'));
        expect(weightText(), contains('—'));
        await tester.tap(toggle);
        await tester.pump();
        void emit(int ms, double grams) {
          watch.elapsed = Duration(milliseconds: ms);
          scale.emit(grams, flow: 99, timerMs: ms, timerRunning: true);
        }

        emit(0, 0);
        emit(500, 1.5);
        emit(1000, 3);
        await tester.pump(const Duration(seconds: 1));
        final target = find.byKey(const ValueKey('flow-target'));
        final actual = find.byKey(const ValueKey('flow-actual'));
        expect(
          tester.widget<Text>(target).data,
          language == 'en' ? '2.0' : '2,0',
        );
        expect(
          tester.widget<Text>(actual).data,
          language == 'en' ? '3.0' : '3,0',
        );
        expect(
          find.byKey(const ValueKey('flow-guide-difference')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ShotGuideChart>(find.byType(ShotGuideChart))
              .trace
              .last
              .value,
          3,
        );
        expect(tester.takeException(), isNull);
        expect(weightText(), contains(language == 'en' ? '3.0' : '3,0'));
        expect(
          tester.widget<Text>(weightDifference).data,
          contains(language == 'en' ? '+1.0' : '+1,0'),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('flow-guide-expected-weight')),
              )
              .data,
          contains(language == 'en' ? '2.0' : '2,0'),
        );
        final fixedPosition = tester.getTopLeft(weight);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -300),
        );
        await tester.pump();
        expect(tester.getTopLeft(weight), fixedPosition);
        expect(weight.hitTestable(), findsOneWidget);
        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.widget<Text>(actual).data, '—');
        expect(weightText(), contains('—'));
        expect(weightDifference, findsNothing);
        expect(
          find.byKey(const ValueKey('flow-guide-difference')),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.widget<Text>(target).data, '—');
        expect(
          timer.running,
          isTrue,
        ); // Reference end never controls the machine.
        final trace = session.flowTrace.points;
        await scale.disconnect();
        await tester.pump();
        expect(timer.running, isFalse);
        expect(weightText(), contains(language == 'en' ? '3.0' : '3,0'));
        expect(tester.widget<Text>(actual).data, '—');
        expect(session.flowTrace.points, trace);
        expect(tester.widget<FilledButton>(toggle).onPressed, isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ShotGuideChart>(find.byType(ShotGuideChart)).trace,
          trace,
        );
        await tester.tap(find.byKey(const ValueKey('flow-guide-reset')));
        await tester.pump();
        expect(session.flowTrace.points, isEmpty);
        expect(session.curve, isNull);
        expect(weightText(), contains('—'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        timer.dispose();
        minutes.dispose();
        seconds.dispose();
        session.dispose();
        scale.dispose();
      },
    );
  }

  testWidgets('weight target stays visible on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final timer = BrewTimer(minutes: minutes, seconds: seconds);
    for (final target in [null, 0.0, double.nan, double.infinity]) {
      await tester.pumpWidget(
        app(
          FlowGuidePage(
            guide: FlowGuide.fromCurve(reference())!,
            title: 'Reference',
            timer: timer,
            targetWeightGrams: target,
          ),
          language: 'es',
          textScale: 2,
        ),
      );
      final weight = find.byKey(const ValueKey('flow-guide-weight'));
      expect(tester.widget<Text>(weight).data, contains('8,0'));
      expect(weight.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    timer.dispose();
    minutes.dispose();
    seconds.dispose();
  });

  testWidgets(
    'reference picker defaults to flow without a sensor and keeps pressure available',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(
        name: 'Scale reference',
        roaster: 'Test',
      );
      final method = await repo.createMethod(
        name: 'Lever',
        category: 'espresso',
      );
      final filter = await repo.createMethod(name: 'V60', category: 'pourover');
      Future<String> save(String methodId, ShotCurve curve) async {
        final id = await repo.createBrew(
          coffeeId: coffee,
          methodId: methodId,
          methodName: methodId == method ? 'Lever' : 'V60',
          doseGrams: 18,
          beverageGrams: 12,
        );
        await repo.saveScaleCurve(id, curve);
        return id;
      }

      final flowId = await save(method, reference());
      final pressureId = await save(
        method,
        ShotCurve(
          timesMs: [0, 1000, 2000],
          pressure: [1, 9, 6],
          flow: [],
          weight: [],
        ),
      );
      await save(filter, reference());
      final before = (await repo.brewCurve(flowId))!.curve.toJson();
      expect((await repo.flowReferences()).map((r) => r.brew.id), [flowId]);
      final model = BrewFormModel(
        repository: repo,
        settings: BrewParameterSettings(db),
        coffees: await repo.allCoffees(),
        initialCoffeeId: coffee,
        initialMethodId: method,
      );
      await tester.pumpWidget(app(PressureReferencePage(model: model)));
      await tester.runAsync(
        () async =>
            await Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final flow = find.byKey(ValueKey('flow-reference-$flowId'));
      expect(flow, findsOneWidget);
      await tester.tap(flow);
      await tester.pumpAndSettle();
      expect(find.byType(FlowGuidePage), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('flow-guide-weight')))
            .data,
        contains('12.0'),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('flow-guide-toggle')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pressure'));
      await tester.runAsync(
        () async =>
            await Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('flow-reference-$flowId')), findsNothing);
      await tester.tap(find.byKey(ValueKey('pressure-reference-$pressureId')));
      await tester.pumpAndSettle();
      expect(find.byType(PressureGuidePage), findsOneWidget);
      final after = await tester.runAsync(() => repo.brewCurve(flowId));
      expect(after!.curve.toJson(), before);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await tester.pumpAndSettle();
    },
  );
}
