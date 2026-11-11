import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

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
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Lock screen coffee', roaster: 'R');
    final coffees = await database.select(database.coffees).get();

    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: BrewForm(
            services: AppServices.forJournal(
              repository,
              parameterSettings: BrewParameterSettings(database),
            ),

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
