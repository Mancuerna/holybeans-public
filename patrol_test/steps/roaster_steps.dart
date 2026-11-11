import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/roasters/roaster_profile_page.dart';
import 'package:patrol/patrol.dart';

Future<void> checkRoasters(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final id = await repo.createCoffee(
    name: 'Archived origin',
    roaster: 'North Star',
    initialGrams: 250,
    paidPriceCents: 1500,
    country: 'Colombia',
  );
  await repo.createBrew(coffeeId: id, methodName: 'V60');
  await repo.setCoffeeArchived(id, archived: true);
  await repo.createCoffee(name: 'Active origin', roaster: ' NORTH  STAR ');
  await repo.createCoffee(name: 'Other coffee', roaster: 'Other roaster');
  final beforeCoffees = await repo.allCoffees();
  final beforeBrews = await repo.allBrews();
  final beforeLots = await repo.coffeeLots(id);
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  final bounds = $.tester.getRect(find.byType(NavigationBar));
  await $.tester.tapAt(
    Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
  );
  await $.pumpAndSettle();
  await $.tap(find.byKey(const ValueKey('roasters-button')));
  await $(find.byKey(const ValueKey('roaster-search'))).enterText('north');
  await $.takeNativeScreenshot('roasters-search');
  expect(find.byKey(const ValueKey('roaster-row-other roaster')), findsNothing);
  await $.tap(find.byKey(const ValueKey('roaster-row-north star')));
  expect(
    $.tester
        .widget<RoasterProfilePage>(find.byType(RoasterProfilePage))
        .profile!
        .coffees
        .length,
    2,
  );
  await $.takeNativeScreenshot('roaster-profile');
  await $.tester.scrollUntilVisible(
    find.byKey(ValueKey('roaster-coffee-$id')),
    250,
    scrollable: find
        .descendant(
          of: find.byType(RoasterProfilePage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await $.pumpAndSettle();
  await Scrollable.ensureVisible(
    $.tester.element(find.byKey(ValueKey('roaster-coffee-$id'))),
    alignment: 0.5,
  );
  await $.pumpAndSettle();
  await $.tap(find.byKey(ValueKey('roaster-coffee-$id')));
  await $.tap(find.byKey(const ValueKey('bean-detail-roaster')));
  expect(find.byType(RoasterProfilePage), findsOneWidget);
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  expect(find.byKey(const ValueKey('bean-detail-roaster')), findsOneWidget);
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  expect(
    $.tester
        .widget<TextField>(find.byKey(const ValueKey('roaster-search')))
        .controller!
        .text,
    'north',
  );
  await $.tap(find.byTooltip('Clear search'));
  expect(
    find.byKey(const ValueKey('roaster-row-other roaster')),
    findsOneWidget,
  );
  expect(await repo.allCoffees(), beforeCoffees);
  expect(await repo.allBrews(), beforeBrews);
  expect(await repo.coffeeLots(id), beforeLots);
}
