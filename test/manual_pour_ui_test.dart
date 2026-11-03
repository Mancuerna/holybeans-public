import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_assistant_page.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_run.dart';

import 'helpers/fake_scale.dart';

void main() {
  for (final locale in ['en', 'es']) {
    testWidgets(
      'manual selection, delayed advance, pause and finish in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final clock = _Clock();
        final feedback = _Feedback();
        final scale = FakeScale(name: 'Test scale', connected: true);
        addTearDown(scale.dispose);
        final notices = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('holybeans/live-update'),
          (call) async {
            notices.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('holybeans/live-update'),
            null,
          ),
        );
        PourAssistantResult? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<PourAssistantResult>(
                          MaterialPageRoute(
                            builder: (_) => PourAssistantPage(
                              plan: PourPlan(
                                doseGrams: 15,
                                ratio: 16,
                                pourIntervalSeconds: 20,
                              ),
                              feedback: feedback,
                              stopwatch: () => clock,
                              scale: scale,
                            ),
                          ),
                        );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final manual = find.byKey(const ValueKey('pour-mode-manual'));
        await tester.scrollUntilVisible(
          manual,
          250,
          scrollable: find
              .descendant(
                of: find.byType(PourAssistantPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(manual);
        await tester.pumpAndSettle();
        await tester.tap(manual);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(manual).selected, isTrue);
        final start = find.byKey(const ValueKey('pour-start'));
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        await tester.tap(start);
        await tester.pump();
        final advance = find.byKey(const ValueKey('pour-advance'));
        final current = find.byKey(const ValueKey('pour-current-step'));
        expect(scale.commands, [ScaleCommand.tareAndStartTimer]);
        for (var i = 0; i < 8; i++) {
          clock.elapsed = Duration(milliseconds: i * 500);
          scale.emit(0);
          await tester.pump(const Duration(milliseconds: 500));
        }
        clock.elapsed = const Duration(seconds: 30);
        scale.emit(240);
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.descendant(
            of: current,
            matching: find.text(
              locale == 'en' ? 'Pour 1 of 3' : 'Vertido 1 de 3',
            ),
          ),
          findsOneWidget,
        );
        final count = feedback.beeps.length;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pour-next-step')),
          100,
          scrollable: find
              .descendant(
                of: find.byType(PourRunView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump(const Duration(seconds: 5));
        expect(feedback.beeps.length, count);
        expect(
          find.text(
            locale == 'en' ? 'When you’re ready' : 'Cuando estés listo',
          ),
          findsOneWidget,
        );
        await tester.tap(advance);
        await tester.pump();
        expect(
          find.text(
            locale == 'en'
                ? 'Next in 20 s, up to 240 g'
                : 'Siguiente en 20 s, hasta 240 g',
          ),
          findsOneWidget,
        );
        expect(
          notices.last.arguments['title'],
          locale == 'en' ? 'Pour 2 of 3' : 'Vertido 2 de 3',
        );
        await tester.tap(find.byKey(const ValueKey('pour-pause')));
        await tester.pump();
        expect(clock.isRunning, isFalse);
        expect(tester.widget<FilledButton>(advance).onPressed, isNull);
        expect(scale.commands.last, ScaleCommand.stopTimer);
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byKey(const ValueKey('pour-pause')));
        await tester.pump();
        expect(scale.commands.last, ScaleCommand.startTimer);
        clock.elapsed = const Duration(seconds: 45);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(advance);
        await tester.pump();
        expect(
          find.text(locale == 'en' ? 'Let it drain' : 'Dejar drenar'),
          findsOneWidget,
        );
        clock.elapsed = const Duration(seconds: 80);
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(const ValueKey('pour-advance')), findsOneWidget);
        await tester.tap(advance);
        await tester.pump();
        expect(find.byKey(const ValueKey('pour-advance')), findsNothing);
        expect(
          notices.last.arguments['title'],
          contains(locale == 'en' ? 'draw down' : 'filtrar'),
        );
        clock.elapsed = const Duration(seconds: 100);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const ValueKey('pour-finish')));
        await tester.pumpAndSettle();
        expect(result!.totalSeconds, 100);
        expect(result!.plan.pourIntervalSeconds, 20);
        expect(
          scale.commands.where((c) => c == ScaleCommand.tareAndStartTimer),
          hasLength(1),
        );
        expect(clock.isRunning, isFalse);
        expect(tester.takeException(), isNull);
        expect(find.byType(PourRunView), findsNothing);
      },
    );
  }
}

class _Feedback extends DeviceFeedback {
  final beeps = <bool>[];
  @override
  Future<void> beep({bool long = false}) async {
    beeps.add(long);
  }

  @override
  Future<void> keepScreenOn(bool on) async {}
}

class _Clock implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
  bool running = false;
  @override
  bool get isRunning => running;
  @override
  void start() {
    running = true;
  }

  @override
  void stop() {
    running = false;
  }

  @override
  void reset() {
    elapsed = Duration.zero;
  }

  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get frequency => 1000000;
}
