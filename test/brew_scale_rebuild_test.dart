import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/brews/brew_scale_reset_button.dart';
import 'package:holybeans/ui/brews/brew_weight_chart.dart';
import 'package:holybeans/ui/brews/extraction_timer.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/app_theme.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

Future<(BrewFormModel, FakeScale)> _mount(
  WidgetTester tester, {
  bool espresso = false,
  String locale = 'en',
  double textScale = 1,
  double padding = 0,
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
    services: AppServices.forJournal(
      repository,
      parameterSettings: BrewParameterSettings(database),
      scale: scale,
    ),

    coffees: await repository.allCoffees(),
    initialCoffeeId: coffee,
    initialMethodId: method,
  );
  addTearDown(() async {
    model.dispose();
    scale.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(locale),
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
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
  for (final locale in ['es', 'en']) {
    for (final (width, textScale) in [(412.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'scale actions fit and cancel waiting: $locale, $width, $textScale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (model, scale) = await _mount(
            tester,
            espresso: true,
            locale: locale,
            textScale: textScale,
            padding: 20,
          );
          final panel = find.byKey(const ValueKey('scale-readout'));
          final wait = find.byKey(const ValueKey('scale-wait-drip'));
          final tare = find.byKey(const ValueKey('scale-tare'));
          final cancel = find.byKey(const ValueKey('scale-wait-drip-cancel'));
          Future<void> reveal(Finder target) async {
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
          }

          void expectInsidePanel(Finder target) {
            final bounds = tester.getRect(panel);
            final button = tester.getRect(target);
            expect(button.left, greaterThanOrEqualTo(bounds.left));
            expect(button.right, lessThanOrEqualTo(bounds.right));
            expect(button.height, greaterThanOrEqualTo(48));
          }

          expect(find.descendant(of: panel, matching: wait), findsOneWidget);
          expect(find.descendant(of: panel, matching: tare), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ExtractionTimerField),
              matching: wait,
            ),
            findsNothing,
          );
          await reveal(tare);
          expectInsidePanel(tare);
          scale.commands.clear();
          await tester.tap(tare);
          await tester.pump();
          expect(scale.commands, [ScaleCommand.tare]);
          expect(model.timer.running, isFalse);
          scale.commands.clear();
          await reveal(wait);
          expectInsidePanel(wait);
          await tester.tap(wait);
          await tester.pump();
          expect(scale.commands, [ScaleCommand.tare]);
          expect(model.scaleSession!.waitingForDrip, isTrue);
          expect(model.timer.running, isFalse);
          expect(
            find.text(
              locale == 'es'
                  ? 'Esperando la primera gota…'
                  : 'Waiting for the first drop…',
            ),
            findsOneWidget,
          );
          await reveal(cancel);
          expectInsidePanel(cancel);
          expect(
            find.text(locale == 'es' ? 'Cancelar espera' : 'Cancel waiting'),
            findsOneWidget,
          );
          await tester.tap(cancel);
          await tester.pump();
          expect(model.scaleSession!.waitingForDrip, isFalse);
          expect(model.timer.running, isFalse);
          expect(wait, findsOneWidget);
          expect(scale.commands, [ScaleCommand.tare]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

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
          find.descendant(
            of: find.byKey(const ValueKey('scale-readout')),
            matching: find.textContaining('99'),
          ),
          findsOneWidget,
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
      expect(tester.widget<FilledButton>(wait).onPressed, isNull);
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
      expect(tester.widget<FilledButton>(wait).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
