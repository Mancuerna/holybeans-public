import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  for (final phase in [CuppingPhase.tasting, CuppingPhase.review]) {
    testWidgets('timer ticks retain scoring controls during ${phase.name}', (
      tester,
    ) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repository = JournalRepository(db);
      final coffee = await repository.createCoffee(
        name: 'Fixture',
        roaster: 'Test',
        initialGrams: 250,
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      final draft =
          CuppingDraft(
              cups: [
                for (var i = 0; i < 6; i++)
                  CuppingCupDraft(coffeeId: coffee, lotId: lot),
              ],
            )
            ..phase = phase
            ..startedAtMs = 1000
            ..timerStartedAtMs = 1000
            ..brokenAtMs = 241000
            ..tastingAtMs = 601000
            ..sound = false;
      final session = (await repository.cuppingSession(
        await repository.createCuppingSession(draft),
      ))!;
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: CuppingPage(repository: repository, session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cupping-view')));
      await tester.pumpAndSettle();
      final scores = find.byType(CuppingScores);
      final model = tester.widget<CuppingScores>(scores).model;
      final fields = find.byType(DropdownButtonFormField<double>);
      expect(fields, findsNWidgets(36));
      final counts = await countWidgetRebuilds(
        {
          'scores': tester.element(scores),
          for (final (index, element) in fields.evaluate().indexed)
            'field$index': element,
        },
        () async {
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
        },
      );
      final totals = {
        'scores': counts['scores'],
        'fields': counts.entries
            .where((entry) => entry.key != 'scores')
            .fold(0, (total, entry) => total + entry.value),
      };
      stdout.writeln('CUPPING_TICK_BUILDS ${phase.name} ${jsonEncode(totals)}');
      expect(totals, {'scores': 0, 'fields': 0});
      tester.widget<DropdownButtonFormField<double>>(fields.first).onChanged!(
        8,
      );
      await tester.pumpAndSettle();
      expect(model.draft.cups.first.rating, 8);
      expect(await model.flush(), isTrue);
      final saved = (await repository.cuppingSession(session.id))!;
      expect(CuppingDraft.fromJson(saved.draftJson).cups.first.rating, 8);
      expect(model.draft.phase, phase);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }
}
