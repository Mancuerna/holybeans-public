import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';

import 'audit_metrics.dart';
import 'journal_fixture.dart';
import 'search_prototype.dart';

Future<void> runJournalAudit(
  JournalFixture fixture,
  AuditRecord record, {
  AuditMemory? memory,
  bool prototypes = true,
}) async {
  final store = await AuditDatabase.open();
  final db = store.database;
  final repository = JournalRepository(db);
  JournalViewModel? model;
  StreamIterator<List<Brew>>? changes;
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
    final read = await timed(() async {
      final rows = await repository.allBrews();
      expect(rows.length, fixture.brews);
    });
    emit('read_all_full_rows', read);

    const projection =
        'SELECT id, coffee_id, method_name, brewed_at_ms, '
        'created_at_ms, rating FROM brews WHERE archived_at_ms IS NULL '
        'ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 50';
    const fullPage =
        'SELECT * FROM brews WHERE archived_at_ms IS NULL '
        'ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 50';
    Future<void> page(String operation, String sql) async {
      final result = await timed(() async {
        final rows = await db.customSelect(sql).get();
        expect(rows.length, 50);
      });
      final plan = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
      emit(operation, {
        ...result,
        'plan': [for (final row in plan) row.data],
      });
    }

    await page('full_page_50_unindexed', fullPage);
    await page('projection_page_50_unindexed', projection);
    await db.customStatement(
      'CREATE INDEX audit_history ON brews '
      '(archived_at_ms, brewed_at_ms DESC, created_at_ms DESC, id ASC)',
    );
    await page('projection_page_50_indexed', projection);
    final firstPage = await db.customSelect(projection).get();
    final cursor = firstPage.last;
    final secondPage = await db
        .customSelect(
          'SELECT id FROM brews WHERE archived_at_ms IS NULL AND '
          '(brewed_at_ms < ? OR (brewed_at_ms = ? AND created_at_ms < ?) OR '
          '(brewed_at_ms = ? AND created_at_ms = ? AND id > ?)) '
          'ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 50',
          variables: [
            Variable(cursor.read<int>('brewed_at_ms')),
            Variable(cursor.read<int>('brewed_at_ms')),
            Variable(cursor.read<int>('created_at_ms')),
            Variable(cursor.read<int>('brewed_at_ms')),
            Variable(cursor.read<int>('created_at_ms')),
            Variable(cursor.read<String>('id')),
          ],
        )
        .get();
    final pageIds = [
      ...firstPage,
      ...secondPage,
    ].map((row) => row.read<String>('id')).toList();
    final expectedIds = (await repository.watchBrews().first)
        .take(100)
        .map((brew) => brew.id)
        .toList();
    expect(pageIds, expectedIds);
    emit('keyset_page_correctness', {'rows': pageIds.length, 'equal': true});
    await db.customStatement('DROP INDEX audit_history');

    store.queries.reset();
    final initial = Stopwatch()..start();
    model = JournalViewModel(
      repository: repository,
      parameterSettings: BrewParameterSettings(db),
      listOptionsSettings: ListOptionsSettings(db),
    );
    await waitForJournal(model);
    initial.stop();
    emit('model_initial_load', {
      'elapsedMs': initial.elapsedMicroseconds / 1000,
      ...store.queries.snapshot,
      ...await memorySnapshot(memory),
    });
    final live = model;
    emit(
      'snapshot_100_reads',
      await timed(() {
        for (var i = 0; i < 100; i++) {
          expect(live.data.brews.length, fixture.brews);
        }
      }),
    );
    final data = live.data;
    final coffees = {for (final coffee in data.coffees) coffee.id: coffee};
    for (final brew in data.brews.take(100)) {
      expect(
        foldWithoutCharacterList(brew.notes ?? ''),
        foldSuggestion(brew.notes ?? ''),
      );
    }
    // Mirrors HistoryTab's text matching only; the actual widget is measured
    // separately. Includes a hit, an accent-folded hit and a full scan miss.
    for (final query in ['audit', 'citrico', 'not-present-needle']) {
      var matches = 0;
      final result = await timed(() {
        matches = 0;
        for (final brew in data.brews) {
          if (brew.archivedAtMs != null) continue;
          if (foldSuggestion(
            '${coffees[brew.coffeeId]?.name ?? ''} '
            '${coffees[brew.coffeeId]?.roaster ?? ''} '
            '${brew.methodName} ${brew.grinderName ?? ''} ${brew.notes ?? ''}',
          ).contains(query)) {
            matches++;
          }
        }
      }, repetitions: 5);
      expect(
        matches,
        query == 'audit' || (query == 'citrico' && fixture.noteCharacters > 0)
            ? fixture.brews - fixture.brews ~/ 10
            : 0,
      );
      emit('search_$query', {...result, 'matches': matches});
      var selected = <int>[];
      final currentSearch = await timed(() {
        selected = selectHistory((
          brews: data.brews,
          coffees: data.coffees,
          query: (
            text: query,
            archived: false,
            ascending: false,
            coffeeId: null,
            methodId: null,
            methodName: null,
            startMs: null,
            endMs: null,
            minimumRating: null,
          ),
        ));
      }, repetitions: 5);
      expect(selected.length, matches);
      emit('history_query_$query', {
        ...currentSearch,
        'matches': selected.length,
      });
      if (!prototypes) continue;
      var prototypeMatches = 0;
      final prototype = await timed(() {
        prototypeMatches = 0;
        for (final brew in data.brews) {
          if (brew.archivedAtMs != null) continue;
          if (foldWithoutCharacterList(
            '${coffees[brew.coffeeId]?.name ?? ''} '
            '${coffees[brew.coffeeId]?.roaster ?? ''} '
            '${brew.methodName} ${brew.grinderName ?? ''} ${brew.notes ?? ''}',
          ).contains(query)) {
            prototypeMatches++;
          }
        }
      }, repetitions: 5);
      expect(prototypeMatches, matches);
      emit('prototype_search_$query', {
        ...prototype,
        'matches': prototypeMatches,
      });
      var metadataFirstCount = 0;
      final metadataFirst = await timed(
        () {
          metadataFirstCount = 0;
          for (final brew in data.brews) {
            if (brew.archivedAtMs != null) continue;
            if (metadataFirstMatches(
              '${coffees[brew.coffeeId]?.name ?? ''} '
              '${coffees[brew.coffeeId]?.roaster ?? ''} '
              '${brew.methodName} ${brew.grinderName ?? ''}',
              brew.notes,
              query,
            )) {
              metadataFirstCount++;
            }
          }
        },
        repetitions: 3,
        warmups: 1,
      );
      expect(metadataFirstCount, matches);
      emit('prototype_metadata_first_$query', {
        ...metadataFirst,
        'matches': metadataFirstCount,
      });
    }
    emit(
      'history_filter_sort',
      await timed(() {
        final visible = data.brews.where((b) => b.archivedAtMs == null).toList()
          ..sort((a, b) {
            final date = b.brewedAtMs.compareTo(a.brewedAtMs);
            if (date != 0) return date;
            final created = b.createdAtMs.compareTo(a.createdAtMs);
            return created != 0 ? created : a.id.compareTo(b.id);
          });
        expect(visible.length, fixture.brews - fixture.brews ~/ 10);
      }),
    );
    emit(
      'statistics_all',
      await timed(() {
        final stats = BrewStats.compute(
          brews: data.brews,
          coffees: data.coffees,
          components: data.components,
          styleOf: (brew) => brewStyleOf(brew, live.methods),
          range: StatsRange.all,
          now: auditNow,
          languageCode: 'en',
        );
        expect(stats, isNotNull);
      }),
    );
    // Last-style lookup is one of the scans freshness performs per coffee.
    emit(
      'last_style_all_coffees',
      await timed(() {
        for (final coffee in data.coffees) {
          lastBrewStyle(coffee.id, data.brews, live.methods);
        }
      }),
    );

    final ratingNotes = data.brews
        .firstWhere((b) => b.id == 'audit-brew-0')
        .notes;
    final saveCoffeeId = data.coffees.first.id;
    changes = StreamIterator(repository.watchBrews(includeArchived: true));
    expect(await changes.moveNext(), isTrue);
    final stream = changes;
    var revision = 0;
    var notifications = 0;
    live.addListener(() => notifications++);
    store.queries.reset();
    final updates = await timed(() async {
      final next = stream.moveNext();
      await repository.rateBrew(
        'audit-brew-0',
        rating: (++revision).isEven ? 3 : 4,
        notes: ratingNotes,
        tasting: const BrewTasting(),
      );
      expect(await next.timeout(const Duration(seconds: 30)), isTrue);
      expect(stream.current.length, fixture.brews);
    }, warmups: 0);
    emit('rate_one_and_receive_history', {
      ...updates,
      ...store.queries.snapshot,
      'modelNotifications': notifications,
      'updates': revision,
      ...await memorySnapshot(memory),
    });
    store.queries.reset();
    final next = stream.moveNext();
    final saveWatch = Stopwatch()..start();
    await repository.createBrew(
      coffeeId: saveCoffeeId,
      methodName: 'V60',
      doseGrams: 18,
      waterGrams: 300,
      brewedAt: auditNow.add(const Duration(days: 1)),
      notes: 'Synthetic audit insertion',
    );
    expect(await next.timeout(const Duration(seconds: 30)), isTrue);
    saveWatch.stop();
    expect(stream.current.length, fixture.brews + 1);
    emit('insert_one_and_receive_history', {
      'elapsedMs': saveWatch.elapsedMicroseconds / 1000,
      ...store.queries.snapshot,
    });
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
    emit('foreign_key_check', {'violations': violations.length});
  } finally {
    await changes?.cancel();
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
