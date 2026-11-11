import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final (locale, width, textScale) in [
    ('es', 390.0, 1.0),
    ('en', 390.0, 1.0),
  ]) {
    testWidgets(
      'water plan keeps timer and amounts visible in $locale at $width / $textScale',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = memoryDatabase();
        addTearDown(db.close);
        final repository = JournalRepository(db);
        final coffee = await repository.createCoffee(
          name: 'Filter',
          roaster: 'Test',
        );
        final method = await repository.createMethod(
          name: 'V60',
          category: 'pourover',
        );
        final scale = FakeScale(name: 'Test scale')..heldOff = true;
        addTearDown(scale.dispose);
        final coffees = await db.select(db.coffees).get();
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(locale),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: BrewForm(
                services: AppServices.forJournal(
                  repository,
                  parameterSettings: BrewParameterSettings(db),
                  scale: scale,
                ),

                coffees: coffees,
                initialCoffeeId: coffee,
                initialMethodId: method,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final model = tester
            .widget<BrewPoursSection>(find.byType(BrewPoursSection))
            .model;
        final draft = model.draft;
        draft.dose.text = '17.2';
        draft.water.text = '275.2';
        draft.pours.bloomCount = 1;
        draft.pours.pourCount = 2;
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('water-plan-timer-toggle'));
        final regular = find.byKey(const ValueKey('extraction-timer'));
        final scrollable = find
            .descendant(
              of: find.byType(BrewForm),
              matching: find.byType(Scrollable),
            )
            .first;
        final tile = find.byKey(const ValueKey('brew-water-plan'));
        await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget);
        expect(regular, findsNothing);
        await tester.scrollUntilVisible(toggle, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(model.timer.running, isTrue);
        expect(toggle.hitTestable(), findsOneWidget);
        final viewport = tester.getRect(scrollable);
        final table = tester.getRect(
          find.byKey(const ValueKey('water-plan-table')),
        );
        final clock = tester.getRect(
          find.byKey(const ValueKey('water-plan-time')),
        );
        expect(table.top, greaterThan(viewport.top));
        expect(table.bottom, lessThan(viewport.bottom));
        expect(clock.top, greaterThan(viewport.top));
        await tester.pump(const Duration(seconds: 3));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('water-plan-time')))
              .data,
          '0:03',
        );
        await tester.tap(find.byKey(const ValueKey('water-plan-mark-bloom')));
        expect(draft.bloom.text, '3');
        await tester.tap(toggle);
        await tester.pump(const Duration(seconds: 2));
        expect(model.timer.elapsedSeconds, 3);
        await tester.tap(toggle);
        await tester.pump(const Duration(seconds: 2));
        expect(model.timer.elapsedSeconds, 5);
        model.timer.stop();
        // Use the real expansion callback as the tile owns its animation state.
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        expect(regular, findsOneWidget);
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget);
        await scale.connect();
        await tester.pumpAndSettle();
        expect(toggle, findsNothing);
        expect(
          find.byKey(const ValueKey('chart-timer-toggle')),
          findsOneWidget,
        );
        await scale.disconnect();
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget);
        model.timer.reset();
        draft.water.text = '1';
        await tester.pumpAndSettle();
        expect(toggle, findsNothing);
        expect(regular, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
