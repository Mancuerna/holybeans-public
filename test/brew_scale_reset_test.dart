import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_scale_reset_button.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';

import 'helpers/fake_scale.dart';

class _ResetScale extends FakeScale {
  _ResetScale() : super(name: 'Test scale', connected: true);

  ScaleCommand? reject;
  Completer<bool>? pendingReset;

  @override
  Future<bool> send(ScaleCommand command) async {
    if (command == reject) return false;
    if (command == ScaleCommand.resetTimer && pendingReset != null) {
      return pendingReset!.future;
    }
    return super.send(command);
  }
}

void main() {
  late _ResetScale scale;
  late BrewDraft draft;
  late BrewDevices devices;
  late BrewTimer timer;

  setUp(() {
    scale = _ResetScale()..emit(36.2);
    draft = BrewDraft();
    draft.water.text = '300';
    timer = BrewTimer(
      minutes: draft.durationMinutes,
      seconds: draft.durationSeconds,
      onStart: (seconds) => devices.timerStarted(seconds),
      onStop: () => devices.timerStopped(),
      onReset: () => devices.timerReset(),
    );
    devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => false,
      scale: scale,
    );
  });

  tearDown(() {
    timer.dispose();
    devices.dispose();
    draft.dispose();
    scale.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ListenableBuilder(
                listenable: devices.scale!,
                builder: (context, _) => ScaleStatusRow(
                  scale: scale,
                  busy: devices.scale!.resetting,
                  resetAction: BrewScaleResetButton(
                    session: devices.scale!,
                    timer: timer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scale.commands.clear();
  }

  final reset = find.byKey(const ValueKey('scale-reset'));

  testWidgets('idle reset clears both values without starting or asking', (
    tester,
  ) async {
    await mount(tester);
    timer.settle(45);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(scale.commands, [ScaleCommand.resetTimer, ScaleCommand.tare]);
    expect(timer.elapsedSeconds, 0);
    expect(timer.running, isFalse);
    expect(devices.scale!.recording, isFalse);
    expect(find.byTooltip('Reset weight and time'), findsOneWidget);
    expect(tester.getSize(reset).width, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'running reset can be cancelled and discards only after confirmation',
    (tester) async {
      await mount(tester);
      timer.toggle();
      await tester.pump();
      await tester.runAsync(() async {
        scale.emit(0);
        await Future<void>.delayed(const Duration(milliseconds: 110));
        scale.emit(20);
      });
      expect(devices.scale!.curve, isNotNull);
      scale.commands.clear();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(timer.running, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(timer.running, isTrue);
      expect(devices.scale!.curve, isNotNull);
      expect(scale.commands, isEmpty);

      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scale-reset-confirm')));
      await tester.pumpAndSettle();
      expect(timer.running, isFalse);
      expect(timer.elapsedSeconds, 0);
      expect(devices.scale!.curve, isNull);
      expect(draft.water.text, '300');
      expect(scale.commands, [ScaleCommand.resetTimer, ScaleCommand.tare]);
      timer.toggle();
      await tester.pump();
      expect(timer.running, isTrue);
      expect(scale.commands.last, ScaleCommand.tareAndStartTimer);
      timer.stop();
      await tester.pump();
    },
  );

  for (final command in [ScaleCommand.resetTimer, ScaleCommand.tare]) {
    testWidgets('reports a failed $command and allows retry', (tester) async {
      await mount(tester);
      scale.reject = command;
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not complete the scale reset.'),
        findsOneWidget,
      );
      expect(timer.running, isFalse);
      if (command == ScaleCommand.resetTimer) expect(scale.commands, isEmpty);
      scale.reject = null;
      scale.commands.clear();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(scale.commands, [ScaleCommand.resetTimer, ScaleCommand.tare]);
    });
  }

  testWidgets(
    'waits for reset before taring and blocks competing starts and taps',
    (tester) async {
      await mount(tester);
      scale.pendingReset = Completer<bool>();
      await tester.tap(reset);
      await tester.pump();
      expect(devices.scale!.resetting, isTrue);
      expect(timer.canStart, isFalse);
      timer.toggle();
      await tester.tap(reset);
      await tester.tap(find.byKey(const ValueKey('scale-tare')));
      scale.emit(36.2, timerMs: 2000, timerRunning: true);
      expect(timer.running, isFalse);
      expect(scale.commands, isEmpty);
      scale.pendingReset!.complete(true);
      await tester.pumpAndSettle();
      expect(scale.commands, [ScaleCommand.tare]);
      expect(timer.canStart, isTrue);
    },
  );

  testWidgets('disconnect during reset prevents tare and reports failure', (
    tester,
  ) async {
    await mount(tester);
    scale.pendingReset = Completer<bool>();
    await tester.tap(reset);
    await tester.pump();
    scale.lose();
    scale.pendingReset!.complete(true);
    await tester.pumpAndSettle();
    expect(scale.commands, isEmpty);
    expect(
      find.textContaining('Could not complete the scale reset.'),
      findsOneWidget,
    );
    expect(reset, findsNothing);
  });

  testWidgets('reset cancels waiting for the first drop', (tester) async {
    await mount(tester);
    devices.scale!.waitForDrip();
    await tester.pump();
    expect(devices.scale!.waitingForDrip, isTrue);
    scale.commands.clear();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(devices.scale!.waitingForDrip, isFalse);
    expect(timer.running, isFalse);
    expect(scale.commands, [ScaleCommand.resetTimer, ScaleCommand.tare]);
  });
}
