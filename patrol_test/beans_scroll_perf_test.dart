import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart' as freshness;
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../benchmark/support/audit_metrics.dart';
import '../benchmark/support/journal_fixture.dart';
import '../benchmark/support/journal_ui_audit.dart';

// Run in the isolated Patrol package, with a fresh process per test. Never
// seed the phone's ordinary journal. First/second passes use the same direction,
// gesture speed and complete list; returning to the top is outside telemetry.
void main() {
  const count = int.fromEnvironment('BEAN_COUNT', defaultValue: 7);
  const run = String.fromEnvironment('BEAN_RUN', defaultValue: 'baseline');
  for (var trial = 0; trial < 2; trial++) {
    // Reverse the order on the second trial to reduce order bias.
    for (final compact in trial == 0 ? [false, true] : [true, false]) {
      final mode = compact ? 'compact' : 'detailed';
      patrolTest('bean scroll $mode trial $trial', ($) async {
        expect(kProfileMode, isTrue, reason: 'device profile mode required');
        final tester = $.tester;
        final directory = (await getExternalStorageDirectory())!;
        final output = File(path.join(directory.path, 'beans-scroll.jsonl'));
        void record(String operation, Map<String, Object?> values) {
          final line = jsonEncode({
            'run': run,
            'mode': mode,
            'trial': trial,
            'coffees': count,
            'photos': 0,
            'operation': operation,
            ...values,
          });
          output.writeAsStringSync(
            '$line\n',
            mode: FileMode.append,
            flush: true,
          );
          debugPrint('BEAN_SCROLL $line', wrapWidth: 100000);
        }

        final store = await AuditDatabase.open();
        try {
          final db = store.database;
          final repository = JournalRepository(db);
          await ListOptionsSettings(db)
              .save(ListOptions(beansCompact: compact));
          await db.transaction(() async {
            for (var i = 0; i < count; i++) {
              final coffee = await repository.createCoffee(
                name: 'Coffee ${i.toString().padLeft(3, '0')}',
                roaster: 'Roaster ${i % 8}',
                country: ['Colombia', 'Ethiopia', 'Kenya'][i % 3],
                region: ['Huila', 'Sidama', 'Nyeri'][i % 3],
                variety: 'Bourbon',
                process: i.isEven ? 'Washed' : 'Natural',
                producer: 'Test producer',
                altitudeMeters: 1800,
                roastDate: DateTime.now()
                    .subtract(Duration(days: 5 + i % 40))
                    .toIso8601String()
                    .substring(0, 10),
                roastLevel: 'light',
                initialGrams: 250,
                flavorProfile: 'chocolate, jasmine, citrus',
              );
              await repository.createBrew(
                coffeeId: coffee,
                methodName: 'V60',
                doseGrams: 15,
                waterGrams: 250,
                brewedAt: DateTime.now().subtract(Duration(days: i + 1)),
              );
            }
            // Newly seeded records must not trigger the 1.4 s add animation.
            await db
                .update(db.coffees)
                .write(
                  CoffeesCompanion(
                    createdAtMs: Value(
                      DateTime.now()
                          .subtract(const Duration(days: 1))
                          .millisecondsSinceEpoch,
                    ),
                  ),
                );
          });

          await tester.pumpWidget(
            HolyBeansApp(
              services: AppServices(database: db),
              initialLocale: const Locale('es'),
            ),
          );
          await settleJournal(tester);
          await destination(tester, 1);
          final tab = tester.widget<BeansTab>(find.byType(BeansTab));
          expect(tab.options.beansCompact, compact);
          expect(tab.data.covers, isEmpty);
          expect(tab.data.coffees, hasLength(count));
          expect(find.byType(Image), findsNothing);
          final list = scrollable(BeansTab);
          final position = tester.state<ScrollableState>(list).position;

          Future<void> scrollPass(int pass) async {
            final collected = <FrameTiming>[];
            void collect(List<FrameTiming> timings) =>
                collected.addAll(timings);
            SchedulerBinding.instance.addTimingsCallback(collect);
            final start = developer.Timeline.now;
            late int end;
            var gestures = 0;
            try {
              do {
                await tester.fling(list, const Offset(0, -450), 1500);
                await tester.pumpAndSettle();
                gestures++;
                expect(gestures, lessThan(count * 3));
              } while (position.extentAfter > 1);
              expect(
                find.text('Coffee ${(count - 1).toString().padLeft(3, '0')}'),
                findsOneWidget,
              );
              end = developer.Timeline.now;
              await Future<void>.delayed(const Duration(milliseconds: 1200));
            } finally {
              SchedulerBinding.instance.removeTimingsCallback(collect);
            }
            final timings = collected.where((frame) {
              final stamp = frame.timestampInMicroseconds(
                FramePhase.vsyncStart,
              );
              return stamp >= start && stamp <= end;
            }).toList();
            expect(timings, isNotEmpty);
            final hz = tester.view.display.refreshRate;
            final budget = 1000 / hz;
            final builds = [
              for (final f in timings) f.buildDuration.inMicroseconds / 1000,
            ];
            final rasters = [
              for (final f in timings) f.rasterDuration.inMicroseconds / 1000,
            ];
            record('scroll', {
              'pass': pass,
              'gestures': gestures,
              'extent': position.maxScrollExtent,
              'frames': timings.length,
              'refreshHz': hz,
              'budgetMs': budget,
              'build': distribution(builds),
              'raster': distribution(rasters),
              'buildOverBudget': builds.where((ms) => ms > budget).length,
              'rasterOverBudget': rasters.where((ms) => ms > budget).length,
              'eitherOverBudget': timings
                  .where(
                    (f) =>
                        f.buildDuration.inMicroseconds / 1000 > budget ||
                        f.rasterDuration.inMicroseconds / 1000 > budget,
                  )
                  .length,
            });
          }

          await scrollPass(1);
          position.jumpTo(0);
          await tester.pumpAndSettle();
          await scrollPass(2);

          // Measure the suspected computation separately, after frame capture.
          final data = tab.data;
          record(
            'freshness_all_uncached',
            await measure(
              () {
                for (final coffee in data.coffees) {
                  freshness.freshnessToday(
                    coffee,
                    data: data,
                    methods: tab.actions.read.methods,
                    portions: tab.actions.read.portions,
                  );
                }
              },
              warmups: 0,
              repetitions: 3,
            ),
          );
          record(
            'freshness_all_cached',
            await measure(
              () {
                for (final coffee in data.coffees) {
                  tab.actions.read.freshnessToday(coffee);
                }
              },
              warmups: 0,
              repetitions: 3,
            ),
          );
          expect(find.byType(BeanCard), findsWidgets);
          expect(tester.takeException(), isNull);
          record('complete', {'passed': true});
          await Future<void>.delayed(const Duration(seconds: 4));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await store.close();
        }
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  }
}
