import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['en', 'es']) {
    final strings = lookupAppLocalizations(Locale(language));
    testWidgets(
      'vessel weighing preserves readable labels and fills beverage ($language)',
      (tester) async {
        final database = memoryDatabase();
        addTearDown(database.close);
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = JournalRepository(database);
        await repository.createCoffee(name: 'Tare coffee', roaster: 'R');
        final methodId = await repository.createMethod(
          name: 'V60',
          category: 'pourover',
          vesselName: 'Hario server',
          vesselGrams: 300,
        );
        final coffees = await database.select(database.coffees).get();

        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: Scaffold(
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

        final total = find.byKey(const ValueKey('brew-jug-total'));
        await tester.scrollUntilVisible(total, 200, scrollable: scrollable);
        await tester.ensureVisible(total);
        await tester.pumpAndSettle();
        expect(
          find.text(strings.jugTare('Hario server', '300')),
          findsOneWidget,
        );
        final beverageLabel = '${strings.brewOutput} (g)';
        final beverage = find.widgetWithText(TextFormField, beverageLabel);
        await tester.ensureVisible(beverage);
        await tester.pumpAndSettle();
        final label = tester.renderObject<RenderParagraph>(
          find.text(beverageLabel),
        );
        expect(
          label.didExceedMaxLines,
          isFalse,
          reason: 'The complete label and units must be readable before typing',
        );
        await tester.ensureVisible(total);
        await tester.enterText(total, '552.5');
        await tester.pump();
        expect(
          tester.widget<TextFormField>(beverage).controller!.text,
          '252.5',
        );
        // The first drip belongs to espresso only.
        expect(find.byKey(const ValueKey('brew-first-drip')), findsNothing);

        await tester.tap(find.text(strings.save).last);
        await tester.pumpAndSettle();
        final brew = await database.select(database.brews).getSingle();
        expect(brew.beverageGrams, 252.5);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }
}
