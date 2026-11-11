import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/ui/cafes/cafe_picker.dart';

import 'helpers/ui_test_support.dart';

class _Cafes extends ListBase<Cafe> {
  _Cafes(this.rows);
  final List<Cafe> rows;
  int reads = 0;
  @override
  int get length => rows.length;
  @override
  set length(int value) => throw UnsupportedError('fixed length');
  @override
  Cafe operator [](int index) {
    reads++;
    return rows[index];
  }

  @override
  void operator []=(int index, Cafe value) => rows[index] = value;
}

void main() {
  testWidgets('search reuses venue metadata and refreshes changed saved rows', (
    tester,
  ) async {
    await tester.runAsync(CafeCatalog.load);
    final cafes = _Cafes([
      for (var i = 0; i < 100; i++)
        Cafe(
          id: 'saved-$i',
          name: 'Café fixture-$i',
          city: 'Test town',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
    ]);
    final refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    CafeInput? selected;
    await tester.pumpWidget(
      localizedApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () async {
              selected = await Navigator.of(context).push<CafeInput>(
                MaterialPageRoute(
                  builder: (_) => ValueListenableBuilder(
                    valueListenable: refresh,
                    builder: (_, _, _) => CafePicker(
                      data: CafeJournalData(
                        cafes,
                        const [],
                        const [],
                        const [],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byType(CafePicker),
      matching: find.byType(ListView),
    );
    // All saved venues, both headers and the existing 60-suggestion limit.
    expect(
      tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
      162,
    );
    cafes.reads = 0;
    for (var i = 0; i < 100; i++) {
      await tester.enterText(find.byType(TextField), 'cafe fixture-${i % 10}');
      await tester.pump();
    }
    final reads = cafes.reads;
    stdout.writeln('CAFE_SEARCH_SAVED_ROW_READS $reads');
    expect(find.text('Café fixture-9'), findsOneWidget);

    // Also recognize changed contents when a parent reuses its list instance.
    cafes[0] = const Cafe(
      id: 'saved-0',
      name: 'Nueva cafetería',
      city: 'New town',
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    refresh.value++;
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'nueva cafeteria');
    await tester.pumpAndSettle();
    expect(find.text('Nueva cafetería'), findsOneWidget);
    expect(find.text('New town'), findsOneWidget);
    expect(
      tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
      3,
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
      162,
    );
    await tester.scrollUntilVisible(
      find.text('Café fixture-99'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('Café fixture-99'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'saved-99');
    expect(selected?.name, 'Café fixture-99');
    expect(selected?.city, 'Test town');
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });
}
