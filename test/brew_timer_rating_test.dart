import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/extraction_timer.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'extraction timer fills minutes and seconds, pauses, resumes and resets',
    (tester) async {
      final database = memoryDatabase();
      final repository = JournalRepository(database);
      await repository.createCoffee(name: 'Timer coffee', roaster: 'Test');
      final coffees = await database.select(database.coffees).get();

      try {
        await _openBrewForm(tester, repository, coffees);
        final scrollable = _formScrollable();
        final timerButton = find.byKey(const ValueKey('extraction-timer'));
        await tester.scrollUntilVisible(
          timerButton,
          240,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        final minutes = find.widgetWithText(TextFormField, 'Minutes');
        final seconds = find.widgetWithText(TextFormField, 'Seconds');
        String text(Finder field) =>
            tester.widget<TextFormField>(field).controller!.text;

        await tester.tap(timerButton);
        await tester.pump();
        expect(find.text('Stop'), findsOneWidget);
        expect((text(minutes), text(seconds)), ('0', '00'));

        await tester.pump(const Duration(seconds: 3));
        expect((text(minutes), text(seconds)), ('0', '03'));

        await tester.tap(timerButton);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Start'), findsOneWidget);
        expect((text(minutes), text(seconds)), ('0', '03'));

        await tester.tap(timerButton);
        await tester.pump(const Duration(seconds: 60));
        expect((text(minutes), text(seconds)), ('1', '03'));

        await tester.tap(find.byKey(const ValueKey('extraction-timer-reset')));
        await tester.pump();
        expect((text(minutes), text(seconds)), ('', ''));
        expect(find.text('Start'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
        await database.close();
      }
    },
  );

  testWidgets('timer keeps running offscreen and saves the full duration', (
    tester,
  ) async {
    final database = memoryDatabase();
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Scroll coffee', roaster: 'Test');
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffees = await database.select(database.coffees).get();
    try {
      await _openBrewForm(tester, repository, coffees, methodId: methodId);
      final timerButton = find.byKey(const ValueKey('extraction-timer'));
      final scrollable = _formScrollable();
      await tester.scrollUntilVisible(timerButton, 240, scrollable: scrollable);
      await tester.pumpAndSettle();
      final minutes = tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Minutes'))
          .controller!;
      final seconds = tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Seconds'))
          .controller!;
      final timer = tester
          .widget<ExtractionTimerField>(find.byType(ExtractionTimerField))
          .timer;
      await tester.tap(timerButton);
      await tester.pump(const Duration(seconds: 3));
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(0);
      await tester.pump();
      expect(
        timerButton.hitTestable(),
        findsNothing,
        reason: 'the timer is outside the visible viewport',
      );
      await tester.pump(const Duration(seconds: 61));
      expect((minutes.text, seconds.text), ('1', '04'));
      expect(timer.running, isTrue);
      await tester.scrollUntilVisible(timerButton, 240, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(find.text('Stop'), findsOneWidget);
      timer.stop();
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final brew = await tester.runAsync(
        () => database.select(database.brews).getSingle(),
      );
      expect(brew!.timeSeconds, 64);

      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await database.close();
    }
  });

  testWidgets(
    'timer start preserves invalid input and shows its inline error',
    (tester) async {
      final database = memoryDatabase();
      final repository = JournalRepository(database);
      await repository.createCoffee(name: 'Timer coffee', roaster: 'Test');
      final coffees = await database.select(database.coffees).get();
      addTearDown(database.close);

      await _openBrewForm(tester, repository, coffees);
      final timerButton = find.byKey(const ValueKey('extraction-timer'));
      await tester.scrollUntilVisible(
        timerButton,
        240,
        scrollable: _formScrollable(),
      );
      await tester.pumpAndSettle();
      final minutes = find.widgetWithText(TextFormField, 'Minutes');
      final seconds = find.widgetWithText(TextFormField, 'Seconds');
      final timer = tester
          .widget<ExtractionTimerField>(find.byType(ExtractionTimerField))
          .timer;
      final error = lookupAppLocalizations(const Locale('en')).invalidDuration;

      await tester.enterText(seconds, '75');
      await tester.tap(timerButton);
      await tester.pump(const Duration(seconds: 3));
      expect(timer.running, isFalse);
      expect(tester.widget<TextFormField>(seconds).controller!.text, '75');
      expect(find.text(error), findsOneWidget);

      await tester.enterText(seconds, '59');
      await tester.enterText(minutes, 'abc');
      await tester.tap(timerButton);
      await tester.pump(const Duration(seconds: 3));
      expect(timer.running, isFalse);
      expect(tester.widget<TextFormField>(minutes).controller!.text, 'abc');
      expect(find.text(error), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('rating starts unset, is set by the slider and can be cleared', (
    tester,
  ) async {
    final database = memoryDatabase();
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Rating coffee', roaster: 'Test');
    final coffees = await database.select(database.coffees).get();

    try {
      await _openBrewForm(tester, repository, coffees);
      final slider = find.descendant(
        of: find.byType(OptionalRatingSlider),
        matching: find.byType(Slider),
      );
      await tester.scrollUntilVisible(
        slider,
        240,
        scrollable: _formScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('No rating'), findsOneWidget);
      expect(find.text('Slide to rate'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      final announced = <String>[];
      tester.getSemantics(slider).visitChildren((child) {
        final data = child.getSemanticsData();
        announced.add('${data.label}|${data.value}');
        return true;
      });
      // An unset rating is announced as such, not as the placeholder 5.
      expect(announced, ['|No rating']);
      semantics.dispose();

      await tester.tap(slider);
      await tester.pumpAndSettle();
      expect(find.text('Rating: 5 / 10'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear rating'));
      await tester.pumpAndSettle();
      expect(find.text('No rating'), findsOneWidget);
      expect(find.byTooltip('Clear rating'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await database.close();
    }
  });
}

Future<void> _openBrewForm(
  WidgetTester tester,
  JournalRepository repository,
  List<Coffee> coffees, {
  String? methodId,
}) async {
  await tester.pumpWidget(
    localizedApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BrewForm(
                  repository: repository,
                  settings: BrewParameterSettings(repository.database),
                  coffees: coffees,
                  initialMethodId: methodId,
                ),
              ),
              child: const Text('Open brew form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open brew form'));
  await tester.pumpAndSettle();
}

Finder _formScrollable() => find
    .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
    .first;
