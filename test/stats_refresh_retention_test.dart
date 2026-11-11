import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/stats/stats_page.dart';

import 'helpers/ui_test_support.dart';

List<Brew> _brews(int count) => [
  for (var i = 0; i < count; i++)
    Brew(
      recipientIsPortafilter: false,
      id: 'b$i',
      coffeeId: 'coffee',
      methodName: 'V60',
      isFavorite: false,
      isPreGround: false,
      brewedAtMs: DateTime(2026, 3).millisecondsSinceEpoch + i * 60000,
      createdAtMs: i,
      updatedAtMs: i,
      doseGrams: 18,
      rating: 8,
    ),
];

class _BrokenBrews extends ListBase<Brew> {
  @override
  int get length => 301;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  Brew operator [](int index) => throw StateError('Fixture refresh failure');
  @override
  void operator []=(int index, Brew value) =>
      throw UnsupportedError('immutable');
}

void main() {
  testWidgets('statistics retain content and scroll through worker refreshes', (
    tester,
  ) async {
    final brews = ValueNotifier(_brews(300));
    addTearDown(brews.dispose);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: ValueListenableBuilder(
          valueListenable: brews,
          builder: (_, rows, _) => StatsPage(
            coffees: const [],
            brews: rows,
            components: const [],
            methods: const [],
            remainingGrams: 0,
            frozenGrams: 0,
            now: DateTime(2026, 3, 20),
          ),
        ),
      ),
    );
    await settleWithWorkers(tester);
    final list = find.byKey(const ValueKey('stats-list'));
    final scroll = verticalScrollable(list);
    var previous = tester.state<ScrollableState>(scroll);
    previous.position.jumpTo(200);
    await tester.pump();
    final offset = previous.position.pixels;
    expect(offset, greaterThan(0));
    var replacements = 0;
    var retainedFrames = 0;
    for (var i = 0; i < 10; i++) {
      brews.value = _brews(301 + i);
      await tester.pump();
      if (list.evaluate().isNotEmpty) retainedFrames++;
      await settleWithWorkers(tester);
      final current = tester.state<ScrollableState>(scroll);
      if (!identical(previous, current)) replacements++;
      previous = current;
    }
    stdout.writeln('STATS_REFRESH_REPLACEMENTS $replacements');
    expect(replacements, 0);
    expect(retainedFrames, 10);
    expect(previous.position.pixels, offset);
    previous.position.jumpTo(0);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stats-overview')),
        matching: find.text('310'),
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    brews.value = _BrokenBrews();
    await tester.pump();
    await settleWithWorkers(tester);
    expect(find.byKey(const ValueKey('stats-refresh-error')), findsOneWidget);
    expect(tester.state<ScrollableState>(scroll), same(previous));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    brews.value = _brews(311);
    await tester.pump();
    await settleWithWorkers(tester);
    expect(find.byKey(const ValueKey('stats-refresh-error')), findsNothing);
    expect(tester.state<ScrollableState>(scroll), same(previous));
    expect(find.text('311'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
