import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/equipment/water_profiles_page.dart';

void main() {
  testWidgets(
    'home, brew and catalog actions remain usable at 2x text on a narrow screen',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = JournalRepository(database);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      addTearDown(database.close);

      final coffeeId = await repository.createCoffee(
        name: 'Ethiopia Guji Uraga Natural Process Reserve',
        roaster: 'A roaster with a deliberately long display name',
        country: 'Ethiopia',
        region: 'Guji Uraga',
        process: 'Natural anaerobic fermentation',
        initialGrams: 250,
        paidPriceCents: 4200,
        notes: 'A long note to make the coffee detail sheet scroll naturally.',
      );
      final methodId = await repository.createMethod(
        name: 'Fellow Stagg X pour over brewer',
        category: 'pourover',
      );
      final grinderId = await repository.createGrinder(
        name: 'Comandante C40 hand grinder',
      );
      final waterProfileId = await repository.createWaterProfile(
        name: 'HolyBeans mineral water for slow pour overs',
        ghPpmAsCaCO3: 60,
        khPpmAsCaCO3: 35,
        tdsPpm: 95,
        ph: 7,
        notes: 'Long water profile notes to exercise wrapping in its card.',
      );
      await repository.createBrew(
        coffeeId: coffeeId,
        methodId: methodId,
        methodName: 'Fellow Stagg X pour over brewer',
        grinderId: grinderId,
        grinderName: 'Comandante C40 hand grinder',
        waterProfileId: waterProfileId,
        doseGrams: 18,
        waterGrams: 288,
        beverageGrams: 252,
        timeSeconds: 180,
        temperatureC: 94,
        tdsPercent: 1.35,
        rating: 8.5,
        notes: 'A long brew note to test the scrollable detail sheet.',
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.text('Ethiopia Guji Uraga Natural Process Reserve'),
        findsWidgets,
      );

      await _tapBottomDestination(tester, 1);
      final beanTabs = find.byKey(const ValueKey('bean-tabs'));
      expect(tester.widget<TabBar>(beanTabs).isScrollable, isTrue);
      expect(
        find.descendant(of: beanTabs, matching: find.byType(FittedBox)),
        findsNothing,
      );
      final searchField = find.byType(TextField).first;
      final sortButton = find.byKey(const ValueKey('bean-sort'));
      final searchBounds = tester.getRect(searchField);
      final sortBounds = tester.getRect(sortButton);
      expect(sortBounds.top, greaterThanOrEqualTo(searchBounds.bottom));
      expect(sortBounds.width, greaterThanOrEqualTo(48));
      expect(sortBounds.right, lessThanOrEqualTo(360));
      expect(
        tester.widget<PopupMenuButton<int>>(sortButton).tooltip,
        'Sort beans: Name, Ascending',
      );
      await tester.tap(sortButton);
      await tester.pumpAndSettle();
      expect(find.byType(CheckedPopupMenuItem<int>), findsNWidgets(7));
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<int>, 'Roast date'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PopupMenuButton<int>>(sortButton).tooltip,
        'Sort beans: Roast date, Descending',
      );
      expect(tester.takeException(), isNull);

      await _tapBottomDestination(tester, 2);
      final historySearch = find.byType(TextField).first;
      final historyFilterButton = find.byKey(
        const ValueKey('history-filter-button'),
      );
      final historySearchBounds = tester.getRect(historySearch);
      final historyFilterBounds = tester.getRect(historyFilterButton);
      // Large text moves the actions below the search, inside the screen.
      expect(
        historyFilterBounds.top,
        greaterThanOrEqualTo(historySearchBounds.bottom),
      );
      expect(historyFilterBounds.height, greaterThanOrEqualTo(48));
      expect(historyFilterBounds.right, lessThanOrEqualTo(360));
      await tester.tap(historyFilterButton);
      await tester.pumpAndSettle();
      final historyFilterScrollable = find.descendant(
        of: find.byKey(const ValueKey('history-filter-sheet')),
        matching: find.byType(Scrollable),
      );
      final historyDateFilter = find.byKey(
        const ValueKey('history-date-filter'),
      );
      await tester.scrollUntilVisible(
        historyDateFilter,
        160,
        scrollable: historyFilterScrollable,
      );
      expect(
        tester
            .getRect(historyDateFilter)
            .overlaps(tester.getRect(historyFilterScrollable)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tapBottomDestination(tester, 1);

      await tester.tap(find.text('Add bean').last);
      await tester.pumpAndSettle();
      final roasterField = find.widgetWithText(TextFormField, 'Roaster');
      final roastLevelField = find.byKey(const ValueKey('coffee-roast-level'));
      expect(
        tester.getRect(roastLevelField).top -
            tester.getRect(roasterField).bottom,
        greaterThanOrEqualTo(20),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Open the bean sheet from the beans list, then follow its primary action into the
      // brew form and confirm the fixed actions and scrolled fields are usable.
      await _tapBottomDestination(tester, 1);
      await tester.tap(
        find.text('Ethiopia Guji Uraga Natural Process Reserve').last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('brew-with-bean-button')),
      );
      expect(
        find.byKey(const ValueKey('brew-with-bean-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('brew-with-bean-button')));
      await tester.pumpAndSettle();
      expect(find.byType(BrewForm), findsOneWidget);
      expect(find.text('Save').last, findsOneWidget);
      expect(find.text('Cancel').last, findsOneWidget);
      final formScrollable = find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final waterProfileField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Water profile (optional)',
      );
      await tester.scrollUntilVisible(
        waterProfileField,
        180,
        scrollable: formScrollable,
      );
      // Form sections are built ahead of the viewport: bring it into view.
      await tester.ensureVisible(waterProfileField);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(waterProfileField)
            .overlaps(tester.getRect(formScrollable)),
        isTrue,
      );
      final grindField = find.widgetWithText(TextFormField, 'Grind setting');
      expect(
        tester.getRect(waterProfileField).top -
            tester.getRect(grindField).bottom,
        greaterThanOrEqualTo(20),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Brew Details keep the primary action full width and the secondary
      // actions reachable as labelled icons at large text.
      await _tapBottomDestination(tester, 0);
      // On Home a coffee's recipe opens the brew it repeats.
      final homeRecipe = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'home-recipe-',
                ),
          )
          .first;
      await tester.ensureVisible(homeRecipe);
      await tester.pumpAndSettle();
      await tester.tap(homeRecipe);
      await tester.pumpAndSettle();
      final repeatAction = find.byKey(const ValueKey('brew-detail-repeat'));
      await tester.ensureVisible(repeatAction);
      await tester.pumpAndSettle();
      final sheetRect = tester.getRect(find.byType(BottomSheet));
      final repeatRect = tester.getRect(repeatAction);
      expect(repeatRect.left, greaterThanOrEqualTo(sheetRect.left));
      expect(repeatRect.right, lessThanOrEqualTo(sheetRect.right));
      expect(repeatRect.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Share brew'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Methods and the water catalog expose their add and save controls while
      // the content itself scrolls inside the sheet.
      Navigator.of(
        tester.element(find.byKey(const ValueKey('brew-detail-edit'))),
      ).pop();
      await tester.pumpAndSettle();
      await _tapBottomDestination(tester, 3);
      expect(find.text('Water'), findsOneWidget);
      await tester.ensureVisible(find.text('Water'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      expect(find.byType(WaterProfilesList), findsOneWidget);
      expect(find.text('Add water profile'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Add water profile'));
      await tester.pumpAndSettle();
      expect(find.text('Save').last, findsOneWidget);
      expect(find.text('Cancel').last, findsOneWidget);
      final semantics = tester.ensureSemantics();
      final hardnessField = find.widgetWithText(
        TextFormField,
        'GH hardness (ppm as CaCO₃)',
      );
      final hardnessData = tester
          .getSemantics(hardnessField)
          .getSemanticsData();
      expect(
        '${hardnessData.label} ${hardnessData.hint}',
        contains('GH hardness (ppm as CaCO₃)'),
      );
      semantics.dispose();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Methods'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Methods'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add method').last);
      await tester.pumpAndSettle();
      expect(find.text('Method name'), findsOneWidget);
      expect(find.text('Save').last, findsOneWidget);
      expect(find.text('Cancel').last, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}

Future<void> _tapBottomDestination(WidgetTester tester, int index) async {
  final navigation = find.byType(NavigationBar);
  final bounds = tester.getRect(navigation);
  await tester.tapAt(
    Offset(bounds.left + bounds.width * (index + 0.5) / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}
