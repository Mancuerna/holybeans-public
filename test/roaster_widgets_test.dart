import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/roasters/roaster_profile_page.dart';
import 'package:holybeans/ui/roasters/roasters_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'roaster_profile_test.dart' show coffee, profiles;

void main() {
  for (final language in ['es', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('profile and directory at 320px $language $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = profiles(
          [
            coffee(
              'Coffee with a long name',
              roaster: 'A very long roaster name to wrap',
              price: 1234567,
              rating: 9,
            ),
          ],
          purchases: [
            (
              coffeeId: 'Coffee with a long name',
              grams: 123456,
              purchaseDate: '2026-10-13',
            ),
          ],
        );
        Widget app(Widget child) => localizedApp(
          locale: Locale(language),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        );
        await tester.pumpWidget(
          app(
            RoasterProfilePage(
              name: data.single.name,
              profile: data.single,
              onOpenCoffee: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('roaster-coffee-Coffee with a long name')),
          200,
          scrollable: verticalScrollable(find.byType(RoasterProfilePage)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(RoastersPage(profiles: data, onOpen: (_) {})),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('roaster-search')),
          'NO MATCH',
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(
            RoasterProfilePage(
              name: 'Missing',
              profile: null,
              onOpenCoffee: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('directory, archived coffee, roaster link and live updates', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(
      name: 'Archived coffee',
      roaster: 'North Star',
      initialGrams: 250,
      paidPriceCents: 1500,
    );
    await repo.setCoffeeArchived(id, archived: true);
    await tester.pumpWidget(
      HolyBeansApp(database: db, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.byKey(const ValueKey('roasters-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('roaster-search')),
      'NORTH',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roaster-row-north star')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('roaster-coffee-$id')),
      200,
      scrollable: verticalScrollable(find.byType(RoasterProfilePage)),
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(ValueKey('roaster-coffee-$id'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('roaster-coffee-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bean-detail-roaster')));
    await tester.pumpAndSettle();
    expect(find.byType(RoasterProfilePage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bean-detail-roaster')), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const ValueKey('bean-detail-roaster'))),
    ).pop();
    await tester.pumpAndSettle();
    await repo.createCoffee(name: 'New coffee', roaster: ' NORTH  STAR ');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RoasterProfilePage>(find.byType(RoasterProfilePage))
          .profile!
          .coffees
          .length,
      2,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('roaster-search')))
          .controller!
          .text,
      'NORTH',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
