import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/year_review/year_review_page.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';

import 'helpers/ui_test_support.dart';
import 'helpers/year_fixture.dart';

class _Reads extends ListBase<Brew> {
  _Reads(this.source);
  final List<Brew> source;
  int reads = 0;
  bool fail = false;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  Brew operator [](int index) {
    if (fail) throw StateError('Fixture year-review failure');
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, Brew value) =>
      throw UnsupportedError('immutable');
}

void main() {
  testWidgets('large year reviews aggregate off the UI and keep latest year', (
    tester,
  ) async {
    final brews = _Reads([
      for (var i = 0; i < 300; i++)
        yearBrew('$i', DateTime(2025 + i % 2, 3), dose: 18, rating: 8),
    ]);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: YearReviewPage(
          brews: brews,
          coffees: [yearCoffee('a')],
          components: yearComponents,
          methods: yearMethods,
          now: DateTime(2026, 10),
        ),
      ),
    );
    await settleWithWorkers(tester);
    final initialReads = brews.reads;
    brews.reads = 0;
    void select(int year) => tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('year-selector')),
        )
        .onChanged!(year);
    YearStoryView story() =>
        tester.widget<YearStoryView>(find.byType(YearStoryView).first);
    for (var i = 0; i < 10; i++) {
      final year = i.isEven ? 2025 : 2026;
      select(year);
      await tester.pump();
      await settleWithWorkers(tester);
      expect(story().year.year, year);
      expect(story().year.count, 150);
      expect(story().year.doseGrams, 2700);
    }
    stdout.writeln(
      'YEAR_REVIEW_UI_READS ${jsonEncode({'initial': initialReads, 'selections': brews.reads})}',
    );
    // Initial year enumeration still reads the journal on the UI isolate.
    expect(initialReads, 300);
    expect(brews.reads, 0);
    select(2025);
    select(2026);
    await tester.pump();
    await settleWithWorkers(tester);
    expect(story().year.year, 2026);
    expect(story().year.count, 150);
    brews.fail = true;
    select(2025);
    await tester.pump();
    await settleWithWorkers(tester);
    expect(find.byKey(const ValueKey('year-review-error')), findsOneWidget);
    expect(story().year.year, 2026);
    brews.fail = false;
    select(2026);
    await tester.pump();
    await settleWithWorkers(tester);
    expect(find.byKey(const ValueKey('year-review-error')), findsNothing);
    expect(story().year.count, 150);
    select(2025);
    await tester.pumpWidget(const SizedBox.shrink());
    await settleWithWorkers(tester);
    expect(tester.takeException(), isNull);
  });
}
