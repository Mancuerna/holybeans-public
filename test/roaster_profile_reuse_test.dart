import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/roasters/roasters_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'roaster profiles reuse snapshots and follow coffees and cafe drinks',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repository = JournalRepository(db);
      await repository.createCoffee(name: 'Fixture', roaster: 'North Star');
      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: db),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      final changeOptions = tester
          .widget<BeansTab>(find.byType(BeansTab))
          .onOptionsChanged!;
      await tester.tap(find.byKey(const ValueKey('roasters-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('roaster-search')),
        'NORTH',
      );
      await tester.pumpAndSettle();
      List<RoasterProfile> profiles() =>
          tester.widget<RoastersPage>(find.byType(RoastersPage)).profiles;
      expect(profiles().single.coffees, hasLength(1));
      var previous = profiles();
      var calculations = 0;
      for (var i = 0; i < 100; i++) {
        changeOptions(ListOptions(beansAscending: i.isEven));
        await tester.pump();
        final current = profiles();
        if (!identical(previous, current)) calculations++;
        previous = current;
      }
      stdout.writeln('ROASTER_PROFILE_CALCULATIONS $calculations');
      expect(calculations, 0);
      await tester.pumpAndSettle();
      await repository.createCoffee(name: 'New fixture', roaster: 'North Star');
      await tester.pumpAndSettle();
      expect(profiles().single.coffees, hasLength(2));
      await repository.cafes.save(
        CafeDrinkInput(
          cafe: const CafeInput(name: 'Fixture cafe'),
          drinkType: 'espresso',
          drankAt: DateTime(2026),
          roaster: 'North Star',
        ),
      );
      await tester.pumpAndSettle();
      expect(profiles().single.cafeDrinks, hasLength(1));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('roaster-search')))
            .controller!
            .text,
        'NORTH',
      );
      expect(
        find.byKey(const ValueKey('roaster-row-north star')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
