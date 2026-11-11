import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/brew_details_sheet.dart';
import 'package:holybeans/ui/brews/history_tab.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/stats/stats_page.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import 'audit_metrics.dart';
import 'journal_fixture.dart';

Future<void> runJournalUiAudit(
  WidgetTester tester,
  JournalFixture fixture,
  AuditRecord record, {
  AuditMemory? memory,
  required Future<void> Function(Finder finder, String text) enterText,
}) async {
  final store = await AuditDatabase.open();
  final repository = JournalRepository(store.database);
  final photos = PhotoStore(
    Directory(path.join(store.directory.path, 'photos')),
  );
  void emit(String operation, Map<String, Object?> values) =>
      record({...fixture.metadata, 'operation': operation, ...values});
  try {
    await fixture.seed(store.database);
    final coffees = await repository.allCoffees();
    final jpeg = Uint8List.fromList(
      img.encodeJpg(
        img.Image(width: 1600, height: 1200)..clear(img.ColorRgb8(90, 60, 30)),
      ),
    );
    for (final coffee in coffees.take(40)) {
      await repository.setCoffeePhotos(coffee.id, [await photos.add(jpeg)]);
    }
    emit('ui_before_mount_memory', await memorySnapshot(memory));
    final mount = Stopwatch()..start();
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: store.database, photos: photos),
        initialLocale: const Locale('en'),
      ),
    );
    await settleJournal(tester);
    mount.stop();
    emit('ui_mount_to_loaded_shell', {
      'elapsedMs': mount.elapsedMicroseconds / 1000,
      'scope': 'in-process shell only; excludes main(), engine and OS startup',
      ...await memorySnapshot(memory),
    });

    Future<void> frames(String name, Future<void> Function() action) async {
      // Profile frame timings are delivered in batches. Filter by the
      // monotonic vsync timestamp so earlier/later frames cannot leak in.
      final collected = <FrameTiming>[];
      void collect(List<FrameTiming> value) => collected.addAll(value);
      SchedulerBinding.instance.addTimingsCallback(collect);
      final start = developer.Timeline.now;
      final watch = Stopwatch()..start();
      late int end;
      try {
        await action();
        watch.stop();
        end = developer.Timeline.now;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(collect);
      }
      final timings = collected.where((frame) {
        final stamp = frame.timestampInMicroseconds(FramePhase.vsyncStart);
        return stamp >= start && stamp <= end;
      }).toList();
      final hz = tester.view.display.refreshRate;
      final budget = 1000 / hz;
      final build = timings
          .map((t) => t.buildDuration.inMicroseconds / 1000)
          .toList();
      final raster = timings
          .map((t) => t.rasterDuration.inMicroseconds / 1000)
          .toList();
      emit(name, {
        'interactionAndSettleMs': watch.elapsedMicroseconds / 1000,
        'refreshHz': hz,
        'budgetMs': budget,
        'frames': timings.length,
        'build': build.isEmpty ? null : distribution(build),
        'raster': raster.isEmpty ? null : distribution(raster),
        'buildOverBudget': build.where((ms) => ms > budget).length,
        'rasterOverBudget': raster.where((ms) => ms > budget).length,
      });
      expect(timings, isNotEmpty, reason: 'device frame telemetry required');
    }

    await frames('ui_history_open', () => destination(tester, 2));
    expect(find.byType(BrewCard).evaluate().length, lessThan(30));
    await frames('ui_history_scroll', () async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(scrollable(HistoryTab), const Offset(0, -600), 1800);
        await tester.pumpAndSettle();
      }
    });
    // Return to the toolbar without including the reset in search timings.
    tester.state<ScrollableState>(scrollable(HistoryTab)).position.jumpTo(0);
    await tester.pumpAndSettle();
    final search = find
        .descendant(
          of: find.byType(HistoryTab),
          matching: find.byType(TextField),
        )
        .first;
    await frames('ui_search_typing', () async {
      for (final text in [
        'c',
        'ci',
        'cit',
        'citr',
        'citri',
        'citric',
        'citrico',
      ]) {
        await enterText(search, text);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, text);
      }
    });
    expect(find.byType(BrewCard), findsWidgets);
    await enterText(search, 'not-present-needle');
    await tester.pumpAndSettle();
    expect(find.byType(BrewCard), findsNothing);
    await enterText(search, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await frames('ui_stats_open', () async {
      await tester.tap(find.byKey(const ValueKey('history-stats-button')));
      await tester.pumpAndSettle();
      expect(find.byType(StatsPage), findsOneWidget);
    });
    Navigator.of(tester.element(find.byType(StatsPage))).pop();
    await tester.pumpAndSettle();

    emit('ui_before_detail_cycles', await memorySnapshot(memory));
    await frames('ui_detail_cycles_10', () async {
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byType(BrewCard).first);
        await tester.pumpAndSettle();
        expect(find.byType(BrewDetailsSheet), findsOneWidget);
        Navigator.of(tester.element(find.byType(BrewDetailsSheet))).pop();
        await tester.pumpAndSettle();
      }
    });
    emit('ui_after_detail_cycles', await memorySnapshot(memory));
    await frames('ui_beans_with_photos', () async {
      await destination(tester, 1);
      for (var i = 0; i < 6; i++) {
        await tester.fling(scrollable(BeansTab), const Offset(0, -600), 1800);
        await tester.pumpAndSettle();
      }
    });
    emit('ui_image_cache', {
      'bytes': PaintingBinding.instance.imageCache.currentSizeBytes,
      'entries': PaintingBinding.instance.imageCache.currentSize,
      'liveImages': PaintingBinding.instance.imageCache.liveImageCount,
      ...await memorySnapshot(memory),
    });
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await store.close();
  }
  emit('ui_unmounted_memory', await memorySnapshot(memory));
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  emit('ui_caches_cleared_memory', await memorySnapshot(memory));
}

Finder scrollable(Type type) => find
    .descendant(
      of: find.byType(type),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<void> destination(WidgetTester tester, int index) async {
  final bounds = tester.getRect(find.byType(NavigationBar));
  await tester.tapAt(
    Offset(bounds.left + bounds.width * (index + 0.5) / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}

Future<void> settleJournal(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pumpAndSettle();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(NavigationBar).evaluate().isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('journal did not finish loading');
}
