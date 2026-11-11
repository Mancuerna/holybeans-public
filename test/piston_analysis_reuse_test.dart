import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/piston/piston_page.dart';

import 'helpers/piston_fake.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

class _Readings extends ListBase<PistonReading> {
  _Readings(this.source);
  final List<PistonReading> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  PistonReading operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, PistonReading value) =>
      throw UnsupportedError('immutable');
}

class _Repository extends PistonRepository {
  _Repository(super.database, this.snapshot);
  PistonSnapshot snapshot;
  final done = Completer<void>();
  late void Function(int) progress;
  @override
  Future<PistonSnapshot> load(String methodId) async => snapshot;
  @override
  Future<void> sync(
    String methodId,
    PistonHistorySource source, {
    required bool Function() cancelled,
    required void Function(int) onProgress,
  }) {
    progress = onProgress;
    return done.future;
  }
}

void main() {
  testWidgets(
    'piston progress reuses analysis and publishes the new snapshot',
    (tester) async {
      final db = memoryDatabase();
      final rows = _Readings(pistonFixture(count: 40));
      final repository = _Repository(db, PistonSnapshot(readings: rows));
      final source = FakePistonSource(const []);
      final connect = connectPistonHistory;
      connectPistonHistory = (_) => source;
      addTearDown(() async {
        connectPistonHistory = connect;
        if (!repository.done.isCompleted) repository.done.complete();
        await db.close();
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: PistonPage(
            repository: repository,
            methodId: 'fixture',
            address: 'test',
            name: 'Fixture',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      PistonChart chart() => tester.widget(find.byType(PistonChart));
      expect(chart().points, hasLength(40));
      await tester.tap(find.byKey(const ValueKey('piston-refresh')));
      await tester.pump();
      rows.reads = 0;
      for (var i = 0; i < 100; i++) {
        repository.progress(i);
        await tester.pump();
      }
      final reads = rows.reads;
      stdout.writeln('PISTON_PROGRESS_READING_ACCESSES $reads');
      repository.snapshot = PistonSnapshot(readings: pistonFixture(count: 41));
      repository.done.complete();
      await tester.pumpAndSettle();
      expect(chart().points, hasLength(41));
      expect(source.closed, isTrue);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Speed'));
      await tester.pumpAndSettle();
      expect(chart().speed, isTrue);
      expect(chart().points.first.raw, 10);
      expect(reads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
