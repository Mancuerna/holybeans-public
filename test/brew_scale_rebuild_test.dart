import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/brews/brew_scale_reset_button.dart';
import 'package:holybeans/ui/brews/brew_weight_chart.dart';
import 'package:holybeans/ui/brews/extraction_timer.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

Future<(BrewFormModel, FakeScale)> _mount(
  WidgetTester tester, {
  bool espresso = false,
}) async {
  final database = memoryDatabase();
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Fixture',
    roaster: 'Test',
  );
  final method = await repository.createMethod(
    name: espresso ? 'Espresso' : 'V60',
    category: espresso ? 'espresso' : 'pourover',
  );
  final scale = FakeScale(name: 'Fixture scale', connected: true)..emit(0);
  final model = BrewFormModel(
    repository: repository,
    settings: BrewParameterSettings(database),
    coffees: await repository.allCoffees(),
    initialCoffeeId: coffee,
    initialMethodId: method,
    scale: scale,
  );
  addTearDown(() async {
    model.dispose();
    scale.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    localizedApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: model,
            builder: (_, _) => BrewTimingSection(model: model),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(model.busy, isFalse);
  return (model, scale);
}

void main() {
  for (final recording in [false, true]) {
    testWidgets(
      '100 readings isolate controls while ${recording ? 'recording' : 'idle'}',
      (tester) async {
        final (model, scale) = await _mount(tester);
        if (recording) {
          model.timer.toggle();
          await tester.pumpAndSettle();
          expect(model.scaleSession!.recording, isTrue);
        }
        Finder builders(Type widget) => find.descendant(
          of: find.byType(widget),
          matching: find.byType(ListenableBuilder),
        );
        final counts = await countWidgetRebuilds(
          {
            'timing': tester.element(builders(BrewTimingSection).first),
            'timerControls': tester.element(
              find
                  .ancestor(
                    of: find.byType(ExtractionTimerField),
                    matching: find.byType(ListenableBuilder),
                  )
                  .first,
            ),
            'reset': tester.element(builders(BrewScaleResetButton)),
            'chart': tester.element(builders(BrewWeightChart).last),
          },
          () async {
            for (var i = 0; i < 100; i++) {
              scale.emit(
                i.toDouble(),
                timerRunning: recording,
                timerMs: recording ? i * 100 : 0,
              );
              await tester.pump();
            }
          },
        );
        stdout.writeln(
          'SCALE_REBUILDS ${jsonEncode({'recording': recording, ...counts})}',
        );
        expect(counts['timing'], 0);
        expect(counts['timerControls'], 0);
        expect(counts['reset'], 0);
        expect(counts['chart'], recording ? 100 : 0);
        expect(
          tester
              .widget<DeviceStatusRow>(
                find.byKey(const ValueKey('scale-readout')),
              )
              .text,
          contains('99'),
        );
        expect(tester.takeException(), isNull);
        model.timer.stop();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'connection, drip waiting and timer controls still follow state',
    (tester) async {
      final (model, scale) = await _mount(tester, espresso: true);
      final wait = find.byKey(const ValueKey('scale-wait-drip'));
      scale.lose();
      await tester.pump();
      expect(find.byKey(const ValueKey('scale-live-chart')), findsNothing);
      expect(tester.widget<TextButton>(wait).onPressed, isNull);
      await scale.connect();
      scale.emit(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('scale-live-chart')), findsOneWidget);
      await tester.tap(wait);
      await tester.pump();
      expect(model.scaleSession!.waitingForDrip, isTrue);
      await tester.tap(find.byKey(const ValueKey('scale-wait-drip-cancel')));
      await tester.pump();
      expect(model.scaleSession!.waitingForDrip, isFalse);
      model.timer.toggle();
      await tester.pump();
      expect(wait, findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Seconds'),
            )
            .controller!
            .text,
        '01',
      );
      model.timer.stop();
      model.timer.reset();
      await tester.pump();
      expect(tester.widget<TextButton>(wait).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
