import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  test('tasting is validated, kept on recipe edits and backed up', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Tasted',
      roaster: 'Test roaster',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
    );
    await repository.rateBrew(
      brewId,
      rating: 7.5,
      notes: ' Juicy ',
      tasting: const BrewTasting(
        balance: -1,
        strength: 0,
        acidity: 4,
        sweetness: 3,
        body: 2,
      ),
    );
    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 19,
      rating: 7.5,
      notes: 'Juicy',
    );
    final brew = await database.select(database.brews).getSingle();
    expect(brew.doseGrams, 19);
    expect(brew.notes, 'Juicy');
    expect(brew.tasteBalance, -1);
    expect(brew.acidity, 4);
    expect(brew.bitterness, isNull);

    await expectLater(
      repository.rateBrew(
        brewId,
        rating: null,
        notes: null,
        tasting: const BrewTasting(acidity: 6),
      ),
      throwsArgumentError,
    );

    final source = await JournalBackup(database).exportJson();
    final target = memoryDatabase();
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(source);
    final restored = await target.select(target.brews).getSingle();
    expect(restored.tasteBalance, -1);
    expect(restored.sweetness, 3);
  });

  testWidgets('the rate sheet records compass, scores and rating', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Rate me',
      roaster: 'Test roaster',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
    );

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 2.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('rate-brew-sheet'));
    Future<void> tapInSheet(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find
            .descendant(of: sheet, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    // Sour and weak: under-extracted and too dilute.
    final cell = find.byKey(const ValueKey('compass--1--1'));
    final emptySize = tester.getSize(find.byKey(const ValueKey('compass-0-0')));
    await tapInSheet(cell);
    // The selected cell keeps the grid's size.
    expect(tester.getSize(cell), emptySize);
    expect(find.textContaining('Extract more'), findsOneWidget);
    expect(find.textContaining('Increase the concentration'), findsOneWidget);
    final radar = find.descendant(
      of: find.byKey(const ValueKey('flavor-radar')),
      matching: find.byType(CustomPaint),
    );
    final before = tester.renderObject<RenderCustomPaint>(radar.first).painter;
    await tapInSheet(find.byKey(const ValueKey('score-Acidity-4')));
    final after = tester.renderObject<RenderCustomPaint>(radar.first).painter!;
    // The radar repaints when a score changes.
    expect(after.shouldRepaint(before!), isTrue);
    await tapInSheet(find.byKey(const ValueKey('score-Body-2')));
    await tester.tap(find.byKey(const ValueKey('rate-brew-save')));
    await tester.pumpAndSettle();

    final brew = await database.select(database.brews).getSingle();
    expect(brew.tasteBalance, -1);
    expect(brew.tasteStrength, -1);
    expect(brew.acidity, 4);
    expect(brew.body, 2);
    expect(find.text('Rating saved'), findsOneWidget);

    await tester.tap(find.text('Rate me'));
    await tester.pumpAndSettle();
    final compass = find.byKey(const ValueKey('brew-detail-compass'));
    await tester.ensureVisible(compass);
    expect(tester.widget<Text>(compass).data, 'Weak, Too sour');
    expect(find.byKey(const ValueKey('flavor-radar')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  for (final reduced in [false, true]) {
    testWidgets('compass transition respects reduced motion: $reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        localizedApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: ExtractionCompass(
              balance: null,
              strength: null,
              onChanged: (_, _) {},
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
            .duration,
        reduced ? Duration.zero : const Duration(milliseconds: 150),
      );
    });
  }
}
