import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_assistant_page.dart';

void main() {
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('changing pour counts preserves unedited numeric precision', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PourAssistantPage(
          plan: PourPlan.toStart(doseGrams: 19, waterGrams: 299.1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total water: 299.1 g'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('One more pour'));
    await tester.tap(find.byTooltip('One more pour'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Total water: 299.1 g'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Total water: 299.1 g'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pour-ratio')),
      -150,
      scrollable: find
          .descendant(
            of: find.byType(PourAssistantPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(find.byKey(const ValueKey('pour-ratio')), '15.8');
    await tester.enterText(find.byKey(const ValueKey('pour-ratio')), '15.7');
    await tester.pumpAndSettle();
    expect(find.text('Total water: 298.3 g'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('brew-ratio-increase')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brew-ratio-increase')));
    await tester.pumpAndSettle();
    expect(find.text('Total water: 304 g'), findsOneWidget);
  });

  testWidgets('the assistant counts down, beeps and moves through the steps', (
    tester,
  ) async {
    final feedback = _FakeFeedback();
    final clock = _HandStopwatch();
    PourAssistantResult? result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PourAssistantPage(
                  plan: PourPlan(
                    doseGrams: 15,
                    ratio: 16,
                    blooms: const [BloomStep(doseMultiple: 2, waitSeconds: 45)],
                  ),
                  feedback: feedback,
                  stopwatch: () => clock,
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
    expect(find.text('3 pours of 70 g; pouring ends at 2:15'), findsOneWidget);

    // Blooms may be removed, including the last one.
    final removeFirst = find.byKey(const ValueKey('pour-remove-bloom-0'));
    expect(tester.widget<IconButton>(removeFirst).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('pour-add-bloom')));
    await tester.pump();
    expect(tester.widget<IconButton>(removeFirst).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('pour-remove-bloom-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pour-remove-bloom-1')), findsNothing);

    // Four pours instead of three.
    await tester.tap(find.byTooltip('One more pour'));
    await tester.pump();
    expect(find.byKey(const ValueKey('pour-count')), findsOneWidget);
    expect(find.textContaining('4 pours of 52.5 g'), findsOneWidget);

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
    await tester.tap(start);
    await tester.pump();
    expect(feedback.screenOn, isTrue);
    expect(feedback.beeps, ['long']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pour-current-step')),
        matching: find.text('Bloom 1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Pour up to 30 g'), findsOneWidget);

    clock.elapsed = const Duration(seconds: 42);
    await tester.pump(const Duration(milliseconds: 250));
    expect(feedback.beeps, ['long', 'short']);
    expect(find.text('Next in 3 s, up to 83 g'), findsOneWidget);

    clock.elapsed = const Duration(seconds: 45, milliseconds: 300);
    await tester.pump(const Duration(milliseconds: 250));
    expect(feedback.beeps.last, 'long');
    expect(find.text('Pour 1 of 4'), findsOneWidget);
    expect(find.text('Pour up to 83 g'), findsOneWidget);

    clock.elapsed = const Duration(minutes: 3, seconds: 5);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('let it draw down'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pour-finish')));
    await tester.pumpAndSettle();
    expect(result!.totalSeconds, 185);
    expect(result!.plan.pours, 4);
    expect(feedback.screenOn, isFalse);
  });

  testWidgets('a finished pour fills the brew and the method remembers it', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Pour coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffees = await database.select(database.coffees).get();
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
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await tester.scrollUntilVisible(dose, 200, scrollable: scrollable);
    await tester.enterText(dose, '20');
    final open = find.byKey(const ValueKey('pour-assistant'));
    await tester.scrollUntilVisible(open, 200, scrollable: scrollable);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(find.text('Total water: 320 g'), findsOneWidget);
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
    await tester.tap(start);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pour-finish')));
    await tester.pumpAndSettle();

    final water = find.widgetWithText(TextFormField, 'Water (g)');
    await tester.scrollUntilVisible(water, -200, scrollable: scrollable);
    expect(tester.widget<TextFormField>(water).controller!.text, '320');
    final method = await database.select(database.brewMethods).getSingle();
    final remembered = PourPlan.fromJson(method.pourPlanJson!, doseGrams: 18);
    expect(remembered.blooms.single.doseMultiple, 2);
    expect(remembered.ratio, 16);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

class _FakeFeedback extends DeviceFeedback {
  final beeps = <String>[];
  bool screenOn = false;

  @override
  Future<void> beep({bool long = false}) async =>
      beeps.add(long ? 'long' : 'short');

  @override
  Future<void> keepScreenOn(bool on) async => screenOn = on;
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
