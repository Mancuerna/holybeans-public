import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';
import 'package:holybeans/ui/cupping/cupping_sessions_page.dart';
import 'package:holybeans/ui/cupping/cupping_setup.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  late AppDatabase db;
  late JournalRepository r;
  late String coffee;
  late String lot;
  setUp(() {
    db = memoryDatabase();
    r = JournalRepository(db);
  });
  Future<void> seed() async {
    coffee = await r.createCoffee(
      name: 'Kenya',
      roaster: 'R',
      initialGrams: 250,
    );
    lot = (await r.coffeeLots(coffee)).single.id;
  }

  tearDown(() => db.close());
  Future<CuppingSession> session(CuppingDraft d) async =>
      (await r.cuppingSession(await r.createCuppingSession(d)))!;
  Widget app(Widget page, {String locale = 'en', double scale = 1}) =>
      localizedApp(
        locale: Locale(locale),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      );

  testWidgets(
    'cupping searches full coffee names and roasters on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const name = 'Diego Barahona - Bourbon Elite Lavado selección especial';
      final selected = await r.createCoffee(
        name: name,
        roaster: 'Tostador Único',
        initialGrams: 250,
      );
      final other = await r.createCoffee(name: 'Other', roaster: 'Different');
      final archived = await r.createCoffee(name: 'Finished', roaster: 'R');
      await r.setCoffeeArchived(archived, archived: true);
      final d = CuppingDraft();
      final m = CuppingModel(r, await session(d), d);
      await m.loadCatalogs();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListenableBuilder(
              listenable: m,
              builder: (_, _) => SingleChildScrollView(
                child: CuppingCupSetup(model: m, index: 0),
              ),
            ),
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('cupping-coffee-0'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('coffee-choice-$archived')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('brew-coffee-search')),
        'tostador unico',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('coffee-choice-$other')), findsNothing);
      final title = find.descendant(
        of: find.text(name),
        matching: find.byType(RichText),
      );
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(find.text('Tostador Único'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('coffee-choice-$selected')));
      await tester.pumpAndSettle();
      expect(d.cups.first.coffeeId, selected);
      expect(d.cups.first.lotId, (await r.coffeeLots(selected)).single.id);
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await m.flush();
      expect(
        CuppingDraft.fromJson((await r.cuppingSession(m.session.id))!.draftJson)
            .cups
            .first
            .coffeeId,
        selected,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'setup rejects empty coffees, updates water and restores its draft',
    (tester) async {
      await seed();
      final row = await session(CuppingDraft());
      await tester.pumpWidget(app(CuppingPage(repository: r, session: row)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cupping-pour')));
      await tester.pump();
      expect(
        find.text(
          'Choose coffee and stock for every cup and check the quantities.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('cupping-dose')),
          matching: find.byType(TextFormField),
        ),
        '8.25',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'SCA suggestion: 150 g of water per cup; adjust to the vessel capacity.',
        ),
        findsOneWidget,
      );
      final builder = tester.widget<ListenableBuilder>(
        find
            .descendant(
              of: find.byType(CuppingPage),
              matching: find.byType(ListenableBuilder),
            )
            .first,
      );
      final model = builder.listenable as CuppingModel;
      await model.flush();
      expect(
        CuppingDraft.fromJson((await r.cuppingSession(row.id))!.draftJson).dose,
        8.25,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in ['en', 'es']) {
    testWidgets('six cups fit 320px at large text in both views ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d =
          CuppingDraft(
              cups: [
                for (var i = 0; i < 6; i++)
                  CuppingCupDraft(coffeeId: coffee, lotId: lot),
              ],
            )
            ..startedAtMs = 1000
            ..brokenAtMs = 241000
            ..tastingAtMs = 721000
            ..phase = CuppingPhase.tasting;
      final row = await session(d);
      await tester.pumpWidget(
        app(
          CuppingPage(repository: r, session: row),
          locale: locale,
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('cupping-finish')))
            .onPressed,
        null,
      );
      await tester.tap(find.byKey(const ValueKey('cupping-view')));
      await tester.pumpAndSettle();
      expect(find.byType(CuppingMatrix), findsOneWidget);
      expect(tester.takeException(), null);
      final horizontal = find.descendant(
        of: find.byType(CuppingMatrix),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      await tester.dragFrom(
        tester.getTopLeft(horizontal) + const Offset(140, 24),
        const Offset(-1500, 0),
      );
      expect(
        tester.state<ScrollableState>(horizontal).position.pixels,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('marking the final score enables finish and commits every cup', (
    tester,
  ) async {
    await seed();
    final d =
        CuppingDraft(
            cups: [
              for (var i = 0; i < 2; i++)
                CuppingCupDraft(coffeeId: coffee, lotId: lot)
                  ..rating = 0
                  ..scores = [1, 2, 3, 4, 5],
            ],
          )
          ..startedAtMs = 1000
          ..brokenAtMs = 241000
          ..tastingAtMs = 721000
          ..phase = CuppingPhase.tasting;
    d.cups[0].scores[4] = null;
    await tester.pumpWidget(
      app(CuppingPage(repository: r, session: await session(d))),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('cupping-finish')))
          .onPressed,
      null,
    );
    final aftertaste = find.widgetWithText(
      DropdownButtonFormField<double>,
      'Aftertaste',
    );
    await tester.scrollUntilVisible(
      aftertaste,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CuppingScores),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(aftertaste);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('cupping-finish')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('cupping-finish')));
    await tester.pumpAndSettle();
    expect(find.text('Cupping saved'), findsOneWidget);
    expect(await r.allBrews(), hasLength(2));
    expect((await r.coffeeLot(lot))!.remainingGrams, 228);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'selection prefers fresh stock and uses frozen when all coffee is frozen',
    () async {
      await seed();
      final portion = await r.freezeCoffee(
        lotId: lot,
        grams: 250,
        frozenDate: '2026-10-08',
      );
      final d = CuppingDraft();
      final m = CuppingModel(r, await session(d), d);
      await m.loadCatalogs();
      m.chooseCoffee(d.cups.first, coffee);
      expect(d.cups.first.frozenPortionId, portion);
      expect(d.cups.first.lotId, lot);
      await m.flush();
      m.dispose();
    },
  );

  test('starting with insufficient combined stock retains setup and creates no brews', () async {
    await seed();
    final d = CuppingDraft(
      cups: [
        CuppingCupDraft(coffeeId: coffee, lotId: lot),
        CuppingCupDraft(coffeeId: coffee, lotId: lot),
      ],
    )..dose = 150;
    final m = CuppingModel(r, await session(d), d);
    await m.loadCatalogs();
    expect(await m.start(), false);
    expect(m.error, isA<CuppingStockException>());
    expect(d.phase, CuppingPhase.setup);
    expect(d.startedAtMs, null);
    expect(await r.allBrews(), isEmpty);
    expect((await r.coffeeLot(lot))!.remainingGrams, 250);
    m.dispose();
  });

  test(
    'model queues snapshots, recovers the clock and only alerts once',
    () async {
      await seed();
      var now = 1000;
      final d = CuppingDraft(
        cups: [
          CuppingCupDraft(coffeeId: coffee, lotId: lot),
          CuppingCupDraft(coffeeId: coffee, lotId: lot),
        ],
      )..sound = false;
      final m = CuppingModel(r, await session(d), d, clock: () => now);
      await m.loadCatalogs();
      expect(m.canStart, true);
      await m.start();
      now = 301000;
      m.tick();
      expect(d.crustAlerted, true);
      m.breakCrust();
      now = 901000;
      m.tick();
      expect(d.tastingAlerted, true);
      m.taste();
      m.change(() => d.cups[0].notes = 'A');
      final a = m.flush();
      m.change(() => d.cups[0].notes = 'B');
      final b = m.flush();
      expect(await a, true);
      expect(await b, true);
      final restored = CuppingDraft.fromJson(
        (await r.cuppingSession(m.session.id))!.draftJson,
      );
      expect(restored.cups[0].notes, 'B');
      expect(restored.elapsedAt(now), 900);
      expect(restored.crustAlerted && restored.tastingAlerted, true);
      m.dispose();
    },
  );

  testWidgets('session list states the draft and its coffees as phrases', (
    tester,
  ) async {
    await seed();
    await session(
      CuppingDraft(
        cups: [
          CuppingCupDraft(coffeeId: coffee, lotId: lot),
          CuppingCupDraft(coffeeId: coffee, lotId: lot),
        ],
      ),
    );
    await tester.pumpWidget(app(CuppingSessionsPage(repository: r)));
    await tester.pumpAndSettle();
    final subtitle = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.contains('\n'));
    expect(subtitle, contains('Draft, ready to resume'));
    expect(subtitle, contains('2 coffees'));
    expect(subtitle, isNot(contains(' · ')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
