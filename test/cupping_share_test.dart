import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';
import 'package:holybeans/ui/cupping/cupping_share_sheet.dart';
import 'package:intl/intl.dart';

import 'helpers/cupping_share_fixture.dart';

class _Pops extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

void main() {
  late AppDatabase db;
  late JournalRepository r;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    r = JournalRepository(db);
  });
  tearDown(() => db.close());

  test('sharing uses current brews, preserves repeated cups, and never changes stock', () async {
    final original = await cuppingShareFixture(r);
    final brew = original.cups.last.brew!;
    await r.rateBrew(
      brew.id,
      rating: 9,
      notes: 'Edited note',
      tasting: const BrewTasting(acidity: 2),
    );
    await (db.update(db.brews)..where((b) => b.id.equals(brew.id))).write(
      const BrewsCompanion(waterGrams: Value(210)),
    );
    final stock = await db.select(db.coffeeLots).get();
    final data = await r.cuppingShareData(original.session.id);
    expect(data.cups.map((c) => c.letter), ['A', 'B', 'C', 'D', 'E', 'F']);
    expect(data.cups.first.brew!.rating, 0);
    expect(data.cups.first.coffee!.id, data.cups.last.coffee!.id);
    expect(data.cups.last.brew!.notes, 'Edited note');
    expect(data.cups.last.scores.first, 2);
    expect(data.cups.last.grinder!.name, 'Timemore 064S');
    expect(data.cups.last.water!.name, 'Agua B');
    expect(data.commonRecipe, false);
    expect(await db.select(db.coffeeLots).get(), stock);
    expect(
      (await r.cuppingSession(data.session.id))!.draftJson,
      original.session.draftJson,
    );
  });

  test(
    'a deleted cup keeps its position with no stale ratings or notes',
    () async {
      final original = await cuppingShareFixture(r, count: 3);
      await r.deleteBrew(original.cups[1].brew!.id);
      final data = await r.cuppingShareData(original.session.id);
      expect(data.cups.map((c) => c.letter), ['A', 'B', 'C']);
      expect(data.cups[1].brew, null);
      expect(data.cups[1].coffee, null);
      expect(data.cups[1].scores, everyElement(isNull));
      expect(data.commonRecipe, false);
    },
  );

  test('drafts and missing sessions cannot be shared', () async {
    final id = await r.createCuppingSession(CuppingDraft());
    await expectLater(r.cuppingShareData(id), throwsStateError);
    await expectLater(r.cuppingShareData('missing'), throwsStateError);
  });

  Widget app(Widget page, String language, {double scale = 1}) => MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: page,
  );

  for (final (language, count) in [('es', 2), ('en', 6), ('es', 6)]) {
    testWidgets(
      'full PNG and optional notes fit a small screen ($language, $count cups)',
      (tester) async {
        final region = Locale(
          language == 'en' ? 'es' : 'en',
          language == 'en' ? 'ES' : 'GB',
        );
        tester.platformDispatcher.localeTestValue = region;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = await cuppingShareFixture(r, count: count);
        ui.Image? decoded;
        List<int>? png;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    png = await showModalBottomSheet<List<int>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CuppingShareSheet(data: data),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
            language,
            scale: 1.5,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            DateFormat.yMMMd(region.toString()).format(DateTime(2026, 10, 9)),
          ),
          findsOneWidget,
        );
        final card = find.byKey(const ValueKey('cupping-share-card'));
        expect(tester.getSize(card).width, 720);
        expect(
          find.ancestor(of: card, matching: find.byType(FittedBox)),
          findsNothing,
        );
        final horizontal = find.byKey(
          const ValueKey('cupping-share-preview-horizontal'),
        );
        await tester.dragFrom(
          tester.getTopLeft(horizontal) + const Offset(80, 100),
          const Offset(-240, 0),
        );
        await tester.pumpAndSettle();
        final horizontalScrollable = find
            .descendant(of: horizontal, matching: find.byType(Scrollable))
            .first;
        expect(
          tester.state<ScrollableState>(horizontalScrollable).position.pixels,
          greaterThan(0),
        );
        expect(
          find.descendant(of: card, matching: find.text('Cata de la mañana')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Final limpio:'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Agua B')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Timemore 064S'),
          ),
          findsOneWidget,
        );
        final s = lookupAppLocalizations(Locale(language));
        expect(
          find.descendant(
            of: card,
            matching: find.text(s.cuppingIntensityAftertaste),
          ),
          findsOneWidget,
        );
        expect(
          find.text(region.languageCode == 'es' ? '0,0' : '0.0'),
          findsOneWidget,
        );
        expect(find.textContaining('Final limpio:'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('cupping-share-notes')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Final limpio:'), findsNWidgets(count));
        await tester.tap(find.byKey(const ValueKey('cupping-share-dark')));
        await tester.pumpAndSettle();
        final height = tester.getSize(card).height;
        // Export after scrolling: every row and the footer must survive clipping.
        await tester.drag(
          find.byKey(const ValueKey('cupping-share-preview')),
          const Offset(0, -2400),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('cupping-share-confirm')));
          await tester.pump();
          for (var i = 0; i < 100 && png == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          expect(png, isNotNull);
          expect(png!.take(4), [0x89, 0x50, 0x4e, 0x47]);
          final codec = await ui.instantiateImageCodec(
            Uint8List.fromList(png!),
          );
          decoded = (await codec.getNextFrame()).image;
          codec.dispose();
        });
        await tester.pumpAndSettle();
        expect(decoded!.width, 1080);
        expect(decoded!.height, closeTo(height * 1.5, 1));
        decoded!.dispose();
        expect(tester.takeException(), isNull);
        expect(await r.allBrews(), hasLength(count));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('two export callbacks produce one PNG and one pop', (
    tester,
  ) async {
    final data = await cuppingShareFixture(r, count: 2);
    final observer = _Pops();
    List<int>? png;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                png = await showModalBottomSheet<List<int>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CuppingShareSheet(data: data),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final export = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('cupping-share-confirm')),
          )
          .onPressed!;
      export();
      export();
      for (var attempt = 0; png == null && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(png, isNotNull);
    expect(observer.pops, 1);
    expect(find.text('Open'), findsOneWidget);
    expect(await r.allBrews(), hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'only finished sessions expose share and preview cancellation is read only',
    (tester) async {
      final row = (await r.cuppingSession(
        await r.createCuppingSession(CuppingDraft()),
      ))!;
      await tester.pumpWidget(
        app(CuppingPage(repository: r, session: row), 'es'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cupping-share')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final data = await cuppingShareFixture(r, count: 2);
      await tester.pumpWidget(
        app(CuppingPage(repository: r, session: data.session), 'es'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cupping-share')));
      await tester.pumpAndSettle();
      expect(find.byType(CuppingShareSheet), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(CuppingShareSheet), findsNothing);
      expect(await r.allBrews(), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
