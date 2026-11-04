import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/brews/brew_details_sheet.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'helpers/ui_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en_GB'));

  testWidgets('five bottom destinations and Home stats fit a narrow screen', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(database.close);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    final navigation = find.byType(NavigationBar);
    expect(tester.widget<NavigationBar>(navigation).destinations, hasLength(4));
    expect(
      find.descendant(of: navigation, matching: find.text('Equipment')),
      findsOneWidget,
    );
    expect(find.byTooltip('Stats'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    const fabLabels = ['Add bean', 'Add bean', 'Brew', 'Add method'];
    final navigationBounds = tester.getRect(navigation);
    for (var index = 0; index < fabLabels.length; index++) {
      await tester.tapAt(
        Offset(
          navigationBounds.left + navigationBounds.width * (index + 0.5) / 4,
          navigationBounds.center.dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, index);
      expect(find.text(fabLabels[index]), findsOneWidget);
      expect(
        tester
            .getRect(find.byType(FloatingActionButton))
            .overlaps(tester.getRect(navigation)),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Equipment'), findsWidgets);
    await tester.tap(find.text('Grinders'));
    await tester.pumpAndSettle();
    expect(find.text('Add grinder'), findsOneWidget);
    await tester.ensureVisible(find.text('Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(find.text('Add water profile'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(
      Offset(
        navigationBounds.left + navigationBounds.width / 10,
        navigationBounds.center.dy,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('No brews in this period.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Stats count archived records and average only recorded values', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(database.close);

    final repository = JournalRepository(database);
    final archivedCoffee = await repository.createCoffee(
      name: 'Archived coffee',
      roaster: 'Test roaster',
    );
    final activeCoffee = await repository.createCoffee(
      name: 'Active coffee',
      roaster: 'Test roaster',
    );
    await repository.createBrew(
      coffeeId: archivedCoffee,
      methodName: 'V60',
      doseGrams: 18,
      rating: 8.5,
    );
    await repository.createBrew(
      coffeeId: activeCoffee,
      methodName: 'V60',
      doseGrams: 20,
      rating: 9.5,
    );
    await repository.createBrew(coffeeId: activeCoffee, methodName: 'Espresso');
    await repository.setCoffeeArchived(archivedCoffee, archived: true);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stats'));
    await tester.pumpAndSettle();

    expect(
      find.text('Historical metrics include archived beans and brews.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Current inventory excludes archived beans and does not depend on the '
        'period; frozen beans are included.',
      ),
      findsOneWidget,
    );
    final overview = find.byKey(const ValueKey('stats-overview'));
    String valueOf(String label) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.descendant(of: overview, matching: find.text(label)),
                  matching: find.byType(Column),
                ),
                matching: find.byType(Text),
              )
              .at(1),
        )
        .data!;
    expect(valueOf('Brews'), '3');
    expect(valueOf('Coffee ground'), '38 g');
    expect(valueOf('Average dose'), '19 g');
    expect(valueOf('Average rating'), '9 / 10');
    expect(
      find.descendant(of: overview, matching: find.text('2 rated')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('stats-tabs')),
        matching: find.text('Brews'),
      ),
    );
    await tester.pumpAndSettle();
    final topMethod = find.byKey(const ValueKey('stats-methods-0'));
    await tester.scrollUntilVisible(
      topMethod,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('stats-list-brews')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(of: topMethod, matching: find.text('V60')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topMethod, matching: find.text('2 brews, ★ 9')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('history separates local brew date and extraction duration', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    tester.binding.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    addTearDown(
      tester.binding.platformDispatcher.clearAlwaysUse24HourTestValue,
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Pre-ground coffee',
      roaster: 'Test roaster',
    );
    final waterProfileId = await repository.createWaterProfile(
      name: 'TestWater',
    );
    final brewedAt = DateTime(2026, 9, 28, 13, 20);
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      waterProfileId: waterProfileId,
      isPreGround: true,
      doseGrams: 18,
      beverageGrams: 36,
      timeSeconds: 165,
      brewedAt: brewedAt,
    );
    await repository.updateWaterProfile(
      id: waterProfileId,
      name: 'Renamed water',
    );
    final coffee = await database.select(database.coffees).getSingle();
    final brew = await database.select(database.brews).getSingle();
    addTearDown(database.close);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final strings = AppLocalizations.of(
      tester.element(find.text('HolyBeans')),
    )!;
    await tapBottomDestination(tester, 2);

    final deviceLocale = tester.binding.platformDispatcher.locale;
    final regionalDate = formatRegionalDate(brewedAt, deviceLocale);
    final timestamp = DateFormat.yMd(deviceLocale.toString())
        .add_Hm()
        .format(brewedAt);
    final localTime = DateFormat.Hm(deviceLocale.toString()).format(brewedAt);
    expect(find.textContaining(localTime), findsOneWidget);
    expect(find.textContaining(timestamp), findsNothing);
    expect(find.textContaining('2:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Pre-ground coffee'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.textContaining(timestamp), findsOneWidget);
    expect(timestamp, startsWith(regionalDate));
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Water profile'), findsOneWidget);
    expect(find.text('Water profile (optional)'), findsNothing);
    expect(find.text('TestWater'), findsOneWidget);
    expect(find.text('Renamed water'), findsNothing);
    expect(
      tester.getRect(find.text('Time')).bottom,
      lessThanOrEqualTo(
        tester
            .getRect(find.descendant(of: sheet, matching: find.text('2:45')))
            .top,
      ),
    );
    expect(
      find.descendant(of: sheet, matching: find.text('2:45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Pre-ground')),
      findsOneWidget,
    );
    expect(find.text('Grind setting'), findsNothing);
    expect(tester.takeException(), isNull);

    final shared = BrewShareText.build(
      strings: strings,
      coffee: coffee,
      components: const [],
      brew: brew,
      fields: {BrewParameter.date, BrewParameter.grinder, BrewParameter.time},
      dateLocaleName: deviceLocale.toString(),
    );
    expect(shared, contains('${strings.brewDate}: $timestamp'));
    expect(shared, contains('${strings.grinder}: ${strings.preGround}'));
    expect(shared, contains('${strings.extractionDuration}: 2:45'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('brew dates follow the mobile region when app language changes', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'GB',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Regional date coffee',
      roaster: 'Test roaster',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      brewedAt: DateTime(2026, 9, 28, 13, 20),
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);
    final expectedDate = DateFormat.yMd('en_GB').format(DateTime(2026, 9, 28));
    await tester.tap(find.text('Regional date coffee'));
    await tester.pumpAndSettle();
    expect(find.textContaining(expectedDate), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('brew-detail-edit'))))
        .pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-es')),
      300,
    );
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Historial'), findsWidgets);

    await tester.tap(find.text('Regional date coffee'));
    await tester.pumpAndSettle();
    expect(find.textContaining(expectedDate), findsOneWidget);
    expect(find.byKey(const ValueKey('brew-detail-edit')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('brew ratio appears in details and as a form preview', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Ratio coffee',
      roaster: 'Test roaster',
    );
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'V60',
      doseGrams: 18,
      waterGrams: 270,
      beverageGrams: 220,
      brewedAt: DateTime(2026, 9, 28, 13, 20),
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);
    await tester.tap(find.text('Ratio coffee'));
    await tester.pumpAndSettle();
    // In the details sheet; the card behind it shows the ratio too.
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Ratio')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('1:15')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    final ratioPreview = find.text('Ratio: 1:15');
    await tester.scrollUntilVisible(
      ratioPreview,
      200,
      scrollable: verticalScrollable(find.byType(BrewForm)),
    );
    expect(ratioPreview, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('bean and brew detail sheets share width on a narrow screen', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32);
    tester.view.viewPadding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Shared width coffee',
      roaster: 'Test roaster',
      notes: List.filled(
        40,
        'Long coffee detail content for safe area coverage.',
      ).join(' '),
    );
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'V60',
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.text('Shared width coffee').last);
    await tester.pumpAndSettle();
    final beanSheet = find.byType(BottomSheet).last;
    final beanWidth = tester.getSize(beanSheet).width;
    final beanHeight = tester.getSize(beanSheet).height;
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final safeTopInset =
        tester.view.viewPadding.top / tester.view.devicePixelRatio;
    expect(beanHeight, greaterThan(viewportHeight * 0.8));
    expect(beanHeight, lessThanOrEqualTo(viewportHeight));
    expect(tester.getTopLeft(beanSheet).dy, greaterThanOrEqualTo(safeTopInset));
    expect(
      find.descendant(
        of: beanSheet,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );

    Navigator.of(tester.element(beanSheet)).pop();
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);
    await tester.tap(find.text('Shared width coffee').last);
    await tester.pumpAndSettle();
    final brewSheet = find.byType(BottomSheet).last;
    final brewHeight = tester.getSize(brewSheet).height;

    expect(tester.getSize(brewSheet).width, beanWidth);
    expect(brewHeight, greaterThan(0));
    expect(brewHeight, lessThanOrEqualTo(viewportHeight));
    expect(
      find.descendant(
        of: brewSheet,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('brew-detail-edit')), findsOneWidget);
    expect(find.text('BREW DETAILS'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('brew title opens its coffee and closing returns to the brew', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Linked coffee',
      roaster: 'Linked roaster',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 15,
      waterGrams: 250,
      temperatureC: 93,
      notes: List.filled(30, 'Brew tasting notes.').join('\n'),
    );
    await BrewParameterSettings(database)
        .saveHidden({BrewParameter.temperature});
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);
    await tester.tap(find.text('Linked coffee').first);
    await tester.pumpAndSettle();

    final brewSheet = find.byType(BrewDetailsSheet);
    final title = find.descendant(
      of: find.descendant(of: brewSheet, matching: find.byType(DetailHeader)),
      matching: find.text('Linked coffee'),
    );
    expect(find.text('Temperature'), findsNothing);
    final reveal = find.byKey(const ValueKey('brew-detail-hidden'));
    await tester.ensureVisible(reveal);
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(find.text('Temperature'), findsOneWidget);
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(verticalScrollable(brewSheet));
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));

    for (final systemBack in [true, false]) {
      await tester.tap(title);
      await tester.pumpAndSettle();
      final coffeeSheet = find.byType(CoffeeDetailsSheet);
      expect(coffeeSheet, findsOneWidget);
      expect(
        tester.widget<CoffeeDetailsSheet>(coffeeSheet).coffee.id,
        coffeeId,
      );
      if (systemBack) {
        expect(await tester.binding.handlePopRoute(), isTrue);
      } else {
        // Drag from the handle, outside the coffee's scrollable content.
        final sheet = find.byType(BottomSheet).last;
        await tester.dragFrom(
          tester.getTopLeft(sheet) + const Offset(180, 16),
          const Offset(0, 800),
        );
      }
      await tester.pumpAndSettle();
      expect(coffeeSheet, findsNothing);
      expect(brewSheet, findsOneWidget);
      expect(tester.widget<BrewDetailsSheet>(brewSheet).brew.id, brewId);
      expect(find.text('Temperature'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(verticalScrollable(brewSheet))
            .position
            .pixels,
        offset,
      );
    }

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(brewSheet, findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('system Back from another tab returns to Home', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final navigation = find.byType(NavigationBar);

    for (final index in [1, 2, 3]) {
      await tapBottomDestination(tester, index);
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, index);
      // Android's Back reaches the app as a pop of its only route.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
      expect(find.text('HolyBeans'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
