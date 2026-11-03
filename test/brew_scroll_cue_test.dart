import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

void main() {
  testWidgets('brew sheet cues fields below until scrolled to the end', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Scroll cue coffee', roaster: 'Test');
    final coffees = await database.select(database.coffees).get();

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

      final cue = find.byKey(const ValueKey('brew-sheet-scroll-cue'));
      expect(cue, findsOneWidget);

      final scrollable = find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (
        var attempt = 0;
        attempt < 5 && position.extentAfter > 0;
        attempt++
      ) {
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pumpAndSettle();
      }

      expect(cue, findsNothing);
      expect(find.widgetWithText(TextFormField, 'Notes'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open brew form'));
      await tester.pumpAndSettle();

      expect(cue, findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await database.close();
    }
  });
}
