import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';
import 'package:patrol/patrol.dart';

Future<void> checkRecipients(PatrolIntegrationTester $, AppDatabase db) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Recipient test',
    roaster: 'Patrol',
    initialGrams: 250,
  );
  final method = await repo.createMethod(
    name: 'V60',
    category: 'pourover',
    vesselName: 'Default jug',
    vesselGrams: 200,
  );
  final coffees = await db.select(db.coffees).get();
  await $.pumpWidgetAndSettle(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open brew'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: BrewForm(
                    services: AppServices.forJournal(
                      repo,
                      parameterSettings: BrewParameterSettings(db),
                    ),

                    coffees: coffees,
                    initialCoffeeId: coffee,
                    initialMethodId: method,
                    initialDoseGrams: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await $.tap(find.text('Open brew'));
  final scroll = find
      .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
      .first;
  final total = find.byKey(const ValueKey('brew-jug-total'));
  await $.scrollUntilVisible(
    finder: find.byType(RecipientPicker),
    view: scroll,
  );
  await $.tap(find.byTooltip('Add vessel'));
  await $.enterText(find.byKey(const ValueKey('recipient-name')), 'Small jug');
  await $.enterText(
    find.byKey(const ValueKey('recipient-grams')),
    '150',
    hideKeyboard: false,
  );
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  await $.tap(find.widgetWithText(FilledButton, 'Save').last);
  await $.scrollUntilVisible(finder: total, view: scroll);
  await $.enterText(total, '500', hideKeyboard: false);
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  final beverage = find.widgetWithText(TextFormField, 'Beverage weight (g)');
  expect($.tester.widget<TextFormField>(beverage).controller!.text, '350');
  await $.takeNativeScreenshot('recipient-selected');
  await $.tap(find.text('Save').last);
  final brew = await db.select(db.brews).getSingle();
  expect(brew.recipientName, 'Small jug');
  expect(brew.recipientGrams, 150);
  expect(brew.beverageGrams, 350);
  final methodRow = await db.select(db.brewMethods).getSingle();
  expect(methodRow.defaultRecipientId, isNot(brew.recipientId));
  await repo.saveRecipient(
    id: brew.recipientId,
    name: 'Renamed jug',
    emptyGrams: 170,
  );
  await $.pumpWidgetAndSettle(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BrewForm(
          services: AppServices.forJournal(
            repo,
            parameterSettings: BrewParameterSettings(db),
          ),

          coffees: coffees,
          existing: brew,
        ),
      ),
    ),
  );
  await $.scrollUntilVisible(finder: total, view: scroll);
  expect($.tester.widget<TextFormField>(total).controller!.text, '500');
  expect(find.text('Less 150 g for Small jug'), findsOneWidget);
  await $.takeNativeScreenshot('recipient-historical-tare');
}
