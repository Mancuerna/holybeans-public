import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/history_pages.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';

import 'audit_metrics.dart';
import 'journal_fixture.dart';

/// Measures the production bounded read paths. Full-export reads have their
/// own operation and never become the shell's retained snapshot.
Future<void> runJournalAudit(
  JournalFixture fixture,
  AuditRecord record, {
  AuditMemory? memory,
}) async {
  final store = await AuditDatabase.open();
  final db = store.database;
  final repository = JournalRepository(db);
  JournalViewModel? model;
  void emit(String operation, Map<String, Object?> values) =>
      record({...fixture.metadata, 'operation': operation, ...values});
  Future<Map<String, Object>> timed(
    FutureOr<void> Function() action, {
    int warmups = 2,
    int repetitions = 9,
  }) => measure(
    action,
    warmups: warmups,
    repetitions: repetitions,
    memory: memory,
  );
  try {
    await fixture.seed(db);
    emit('seeded_memory', await memorySnapshot(memory));
    store.queries.reset();
    final initial = Stopwatch()..start();
    final live = model = JournalViewModel(
      repository: repository,
      parameterSettings: BrewParameterSettings(db),
      listOptionsSettings: ListOptionsSettings(db),
    );
    await waitForJournal(live);
    initial.stop();
    expect(live.data.overview!.count, fixture.brews);
    expect(
      live.data.brews.length,
      lessThanOrEqualTo(live.data.coffees.length * 3),
    );
    expect(
      live.data.brews.every(
        (row) => row.notes == null && row.pourPhasesJson == null,
      ),
      isTrue,
    );
    emit('model_initial_load', {
      'elapsedMs': initial.elapsedMicroseconds / 1000,
      'retainedPreviews': live.data.brews.length,
      'totalBrews': live.data.overview!.count,
      ...store.queries.snapshot,
      ...await memorySnapshot(memory),
    });
    emit(
      'snapshot_100_reads',
      await timed(() {
        for (var i = 0; i < 100; i++) {
          expect(live.data.overview!.count, fixture.brews);
        }
      }),
    );
    final pages = HistoryPages(repository.reads);
    for (final text in ['', 'audit', 'citrico', 'not-present-needle']) {
      final HistoryQuery query = (
        text: text,
        archived: false,
        ascending: false,
        coffeeId: null,
        methodId: null,
        methodName: null,
        startMs: null,
        endMs: null,
        minimumRating: null,
      );
      late HistoryPage page;
      final timing = await timed(() async {
        page = await pages.page(query, live.data.coffees);
      }, repetitions: 5);
      final hasMatches =
          text != 'not-present-needle' &&
          (text != 'citrico' || fixture.noteCharacters > 0);
      expect(page.rows.length, hasMatches ? 50 : 0);
      expect(page.rows.every((row) => row.notes == null), isTrue);
      emit('history_first_page_${text.isEmpty ? 'unfiltered' : text}', {
        ...timing,
        'rows': page.rows.length,
        'more': page.more,
      });
    }
    const HistoryQuery query = (
      text: '',
      archived: false,
      ascending: false,
      coffeeId: null,
      methodId: null,
      methodName: null,
      startMs: null,
      endMs: null,
      minimumRating: null,
    );
    final first = await pages.page(query, live.data.coffees);
    final second = await pages.page(
      query,
      live.data.coffees,
      after: first.next,
      expectedRevision: first.revision,
    );
    final ids = [...first.rows, ...second.rows].map((row) => row.id).toList();
    final expected = await db
        .customSelect(
          'SELECT id FROM brews WHERE archived_at_ms IS NULL ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 100',
        )
        .get();
    expect(ids, expected.map((row) => row.read<String>('id')));
    emit('keyset_page_correctness', {'rows': ids.length, 'equal': true});
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT id FROM brews WHERE archived_at_ms IS NULL ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 50',
        )
        .get();
    emit('history_query_plan', {
      'plan': [for (final row in plan) row.data],
    });

    final original = (await repository.brew('audit-brew-0'))!;
    var revision = 0;
    var notifications = 0;
    live.addListener(() => notifications++);
    Future<void> changed(Future<void> Function() write) async {
      final before = live.data.overview;
      final ready = Completer<void>();
      void listener() {
        if (live.data.overview != before && !ready.isCompleted) {
          ready.complete();
        }
      }

      live.addListener(listener);
      try {
        await write();
        await ready.future.timeout(const Duration(seconds: 30));
      } finally {
        live.removeListener(listener);
      }
    }

    store.queries.reset();
    final updates = await timed(
      () => changed(
        () => repository.rateBrew(
          original.id,
          rating: (++revision).isEven ? 3 : 4,
          notes: original.notes,
          tasting: const BrewTasting(),
        ),
      ),
      warmups: 0,
    );
    emit('rate_one_and_receive_overview', {
      ...updates,
      ...store.queries.snapshot,
      'modelNotifications': notifications,
      'updates': revision,
      ...await memorySnapshot(memory),
    });
    final watch = Stopwatch()..start();
    await changed(() async {
      await repository.createBrew(
        coffeeId: live.data.coffees.first.id,
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 300,
        brewedAt: auditNow.add(const Duration(days: 1)),
        notes: 'Synthetic audit insertion',
      );
    });
    watch.stop();
    expect(live.data.overview!.count, fixture.brews + 1);
    emit('insert_one_and_receive_overview', {
      'elapsedMs': watch.elapsedMicroseconds / 1000,
    });
    emit(
      'analytics_without_notes',
      await timed(() async {
        final rows = await repository.reads.analytics();
        expect(rows.length, fixture.brews + 1);
        expect(
          rows.every((row) => row.notes == null && row.pourPhasesJson == null),
          isTrue,
        );
      }),
    );
    emit(
      'read_all_full_rows',
      await timed(() async {
        expect(await repository.allBrews(), hasLength(fixture.brews + 1));
      }),
    );
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
    emit('foreign_key_check', {'violations': violations.length});
  } finally {
    model?.dispose();
    await store.close();
  }
  emit('closed_memory', await memorySnapshot(memory));
}

Future<void> waitForJournal(JournalViewModel model) async {
  if (!model.loading) return;
  final ready = Completer<void>();
  void changed() {
    if (!model.loading && !ready.isCompleted) ready.complete();
  }

  model.addListener(changed);
  try {
    await ready.future.timeout(const Duration(seconds: 60));
    expect(model.hasError, isFalse);
  } finally {
    model.removeListener(changed);
  }
}
