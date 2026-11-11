import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

import 'helpers/ui_test_support.dart';

class _HeldCatalog extends QueryInterceptor {
  _HeldCatalog(this.table, {this.fail = false});

  final String table;
  bool fail;
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool held = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (armed && !held && statement.contains(table)) {
      held = true;
      entered.complete();
      await release.future;
      if (fail) throw StateError('Catalog unavailable');
    }
    return executor.runSelect(statement, args);
  }
}

Future<String> _open(
  WidgetTester tester,
  _HeldCatalog reads, {
  String category = 'espresso',
  bool adjust = false,
}) async {
  final db = AppDatabase.forTesting(
    NativeDatabase.memory().interceptWith(reads),
  );
  addTearDown(db.close);
  final repository = JournalRepository(db);
  final coffeeId = await repository.createCoffee(
    name: 'Loading coffee',
    roaster: 'R',
  );
  final methodId = await repository.createMethod(
    name: 'Lever',
    category: category,
  );
  final coffees = await repository.allCoffees();
  reads.armed = true;
  await tester.pumpWidget(
    localizedApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFormSheet<void>(
              context,
              BrewForm(
                services: AppServices.forJournal(
                  repository,
                  parameterSettings: BrewParameterSettings(db),
                ),

                coffees: coffees,
                initialCoffeeId: coffeeId,
                initialMethodId: methodId,
                adjust: adjust,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.runAsync(
    () => reads.entered.future.timeout(const Duration(seconds: 5)),
  );
  await tester.pump();
  return methodId;
}

void main() {
  for (final table in [
    'brew_methods',
    'grinders',
    'water_profiles',
    'recipients',
    'coffee_lots',
    'method_tools',
  ]) {
    testWidgets('the complete form waits for $table without flashing bars', (
      tester,
    ) async {
      final reads = _HeldCatalog(table);
      final methodId = await _open(tester, reads);
      expect(find.byType(BrewChoiceSection), findsNothing);
      expect(find.byType(BrewEquipmentSection), findsNothing);
      expect(find.byType(BrewRecipeSection), findsNothing);
      expect(find.byType(BrewTimingSection), findsNothing);
      expect(find.byType(BrewResultSection), findsNothing);
      expect(find.byKey(const ValueKey('brew-recipe-header')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      reads.release.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('method:$methodId')), findsOneWidget);
      expect(find.byKey(const ValueKey('brew-recipe-header')), findsOneWidget);
      expect(find.byType(BrewChoiceSection), findsOneWidget);
      expect(find.byType(BrewEquipmentSection), findsOneWidget);
      expect(find.byType(BrewRecipeSection), findsOneWidget);
      expect(find.byType(BrewTimingSection), findsOneWidget);
      expect(find.byType(BrewResultSection), findsOneWidget);
      expect(find.byKey(const ValueKey('brew-pressure')), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Water (g)'), findsNothing);
      expect(find.byKey(const ValueKey('pour-assistant')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  testWidgets('a quick filter load reveals the form without an indicator', (
    tester,
  ) async {
    final reads = _HeldCatalog('brew_methods');
    await _open(tester, reads, category: 'pourover');
    reads.release.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Water (g)'), findsOneWidget);
    expect(find.byKey(const ValueKey('brew-pressure')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed initial read can retry without exposing an incomplete form',
    (tester) async {
      final reads = _HeldCatalog('grinders', fail: true);
      await _open(tester, reads);
      reads.release.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('brew-load-error')), findsOneWidget);
      expect(find.byType(BrewChoiceSection), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Retry'));
      // Retrying a failed stream includes asynchronous cancellation and SQL;
      // pumpAndSettle alone can stop while that work schedules no frames.
      for (
        var i = 0;
        i < 100 && find.byType(BrewChoiceSection).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('brew-load-error')), findsNothing);
      expect(find.byType(BrewChoiceSection), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('Cancel stays available while Adjust is loading', (tester) async {
    final reads = _HeldCatalog('brew_methods');
    await _open(tester, reads, adjust: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(BrewForm), findsNothing);
    reads.release.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
