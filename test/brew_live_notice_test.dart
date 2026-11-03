import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

void main() {
  testWidgets('the running timer shows as an ongoing notice until it stops', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('holybeans/live-update');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Lock screen coffee', roaster: 'R');
    final coffees = await database.select(database.coffees).get();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BrewForm(
            repository: repository,
            settings: BrewParameterSettings(database),
            coffees: coffees,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final timer = find.byKey(const ValueKey('extraction-timer'));
    await tester.scrollUntilVisible(
      timer,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(timer);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.map((call) => call.method), ['show']);
    expect((calls.single.arguments as Map)['title'], 'Lock screen coffee');

    await tester.tap(timer);
    await tester.pump();
    expect(calls.map((call) => call.method), ['show', 'clear']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
