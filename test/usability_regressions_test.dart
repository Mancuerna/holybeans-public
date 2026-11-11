import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/beans/coffee_form_model.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/brews/history_filter_chips.dart';
import 'package:holybeans/ui/brews/history_filters.dart';
import 'package:holybeans/ui/brews/history_tab.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en_GB'));
  for (final lang in ['es', 'en']) {
    void viewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    Widget app(Widget child) => localizedApp(
      theme: AppTheme.light(),
      locale: Locale(lang),
      home: Scaffold(body: child),
    );

    Future<void> bottom(WidgetTester tester) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final state = tester.state<ScrollableState>(
        verticalScrollable(find.byType(CoffeeForm)),
      );
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    for (final edit in [false, true]) {
      testWidgets(
        'price validation survives scrolling and preserves data $lang edit=$edit',
        (tester) async {
          viewport(tester);
          final db = memoryDatabase();
          addTearDown(db.close);
          final repo = JournalRepository(db);
          final id = edit
              ? await repo.createCoffee(
                  name: 'Original',
                  roaster: 'Test',
                  initialGrams: 250,
                  paidPriceCents: 1000,
                )
              : null;
          final before = await db.select(db.coffees).get();
          final lots = await db.select(db.coffeeLots).get();
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFormSheet<bool>(
                    context,
                    CoffeeForm(
                      repository: repo,
                      existing: before.firstOrNull,
                      lots: lots,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          if (!edit) {
            await tester.enterText(
              find.widgetWithText(
                TextFormField,
                lang == 'es' ? 'Nombre del café' : 'Coffee name',
              ),
              'New bean',
            );
          }
          final price = find.widgetWithText(
            TextFormField,
            lang == 'es' ? 'Precio pagado (€)' : 'Paid price (€)',
          );
          await tester.ensureVisible(price);
          await tester.pumpAndSettle();
          await tester.enterText(price, '12,345');
          await bottom(tester);
          expect(price.hitTestable(), findsNothing);
          await tester.tap(find.text(lang == 'es' ? 'Guardar' : 'Save'));
          await tester.pumpAndSettle();
          expect(price.hitTestable(), findsOneWidget);
          final strings = AppLocalizations.of(tester.element(price));
          expect(find.text(strings.invalidPrice).hitTestable(), findsOneWidget);
          expect(await db.select(db.coffees).get(), before);
          expect(await db.select(db.coffeeLots).get(), lots);
          await tester.enterText(price, '12,34');
          await bottom(tester);
          await tester.tap(find.text(strings.save));
          await tester.pumpAndSettle();
          final saved = (await db.select(db.coffees).get()).single;
          expect(saved.paidPriceCents, 1234);
          if (edit) expect(saved.id, id);
          expect(find.byType(CoffeeForm), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }

    testWidgets('missing name is revealed from bottom $lang', (tester) async {
      viewport(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(
        app(CoffeeForm(repository: JournalRepository(db))),
      );
      await tester.pumpAndSettle();
      await bottom(tester);
      await tester.tap(find.text(lang == 'es' ? 'Guardar' : 'Save'));
      await tester.pumpAndSettle();
      expect(
        find
            .text(
              lang == 'es'
                  ? 'Este campo es obligatorio'
                  : 'This field is required',
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(await db.select(db.coffees).get(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'coffee picker searches roaster and accents, cancel preserves choice $lang',
      (tester) async {
        viewport(tester);
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final first = await repo.createCoffee(
          name: 'Café Etiopía',
          roaster: 'Aurora',
          initialGrams: 100,
        );
        final second = await repo.createCoffee(
          name: 'Colombia',
          roaster: 'Otro',
          initialGrams: 100,
        );
        final coffees = await repo.allCoffees();
        var selected = second;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, setState) => CoffeePicker(
                repository: repo,
                coffees: coffees,
                value: selected,
                onChanged: (id) => setState(() => selected = id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> open() async {
          await tester.tap(find.byKey(const ValueKey('brew-coffee-picker')));
          await tester.pumpAndSettle();
        }

        await open();
        final search = find.byKey(const ValueKey('brew-coffee-search'));
        await tester.enterText(search, 'etiopia');
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('coffee-choice-$first')), findsOneWidget);
        expect(find.byKey(ValueKey('coffee-choice-$second')), findsNothing);
        Navigator.of(tester.element(search)).pop();
        await tester.pumpAndSettle();
        expect(selected, second);
        await open();
        await tester.enterText(search, 'aurora');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('coffee-choice-$first')));
        await tester.pumpAndSettle();
        expect(selected, first);
        expect(find.text('Café Etiopía'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('history search, compare and repeat are reachable $lang', (
      tester,
    ) async {
      viewport(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(
        name: 'Café Etiopía',
        roaster: 'Aurora',
        initialGrams: 250,
      );
      final method = await repo.createMethod(name: 'V60', category: 'pourover');
      final ids = <String>[];
      for (var i = 0; i < 2; i++) {
        ids.add(
          await repo.createBrew(
            coffeeId: coffee,
            methodId: method,
            methodName: 'V60',
            doseGrams: 18,
            waterGrams: 288,
            notes: 'Long tasting notes ' * 20,
          ),
        );
      }
      final before = await db.select(db.brews).get();
      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: db),
          initialLocale: Locale(lang),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 2);
      final search = find.descendant(
        of: find.byType(HistoryTab),
        matching: find.byType(TextField),
      );
      for (final query in ['cafe', 'etiopia', 'aurora']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('brew-card-${ids.last}')), findsOneWidget);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('brew-card-${ids.last}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('brew-detail-repeat')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('brew-detail-compare')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('compare-with-${ids.first}')));
      await tester.pumpAndSettle();
      expect(await db.select(db.brews).get(), before);
      expect(find.byType(BrewComparisonPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(BrewComparisonPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('brew-card-${ids.last}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brew-detail-repeat')));
      await tester.pumpAndSettle();
      expect(find.byType(BrewForm), findsOneWidget);
      expect(await db.select(db.brews).get(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('active filters wrap and quick periods apply $lang', (
      tester,
    ) async {
      viewport(tester);
      final filters = HistoryFilters()
        ..methodName = 'V60'
        ..minimumRating = 8;
      addTearDown(filters.dispose);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ListenableBuilder(
              listenable: filters,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    IconButton(
                      key: const ValueKey('history-filter-button'),
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => showHistoryFilters(
                        context,
                        filters,
                        coffees: const [],
                        methods: const ['V60'],
                      ),
                    ),
                    HistoryFilterChips(filters: filters, coffees: const []),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('history-active-rating')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-active-method')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('history-filter-button')));
      await tester.pumpAndSettle();
      final today = DateUtils.dateOnly(DateTime.now());
      for (final (period, start) in [
        ('today', today),
        ('week', DateTime(today.year, today.month, today.day - 6)),
        ('month', DateTime(today.year, today.month)),
      ]) {
        final choice = find.byKey(ValueKey('history-period-$period'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(filters.dateRange, DateTimeRange(start: start, end: today));
      }
      Navigator.of(
        tester.element(find.byKey(const ValueKey('history-filter-sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(lang == 'es' ? 'Borrar filtros' : 'Clear filters'),
      );
      await tester.pumpAndSettle();
      expect(filters.activeCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test('model rejects invalid price before updating a saved coffee', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(
      name: 'Keep me',
      roaster: 'Test',
      paidPriceCents: 1000,
    );
    final coffee = (await repo.allCoffees()).single;
    final model = CoffeeFormModel(repository: repo, existing: coffee);
    addTearDown(model.dispose);
    model.paidPrice.text = '12,345';
    await expectLater(model.save([]), throwsFormatException);
    expect((await repo.coffee(id))!.paidPriceCents, 1000);
    expect(model.saving, isFalse);
  });
}
