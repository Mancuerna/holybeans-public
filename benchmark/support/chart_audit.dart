import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/app_theme.dart';

import 'audit_metrics.dart';

Future<void> runChartAudit(
  WidgetTester tester,
  AuditRecord record, {
  AuditMemory? memory,
}) async {
  for (final points in [300, 3000, 10000]) {
    final curve = ValueNotifier(_curve(points));
    final collected = <FrameTiming>[];
    void collect(List<FrameTiming> value) => collected.addAll(value);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: ValueListenableBuilder(
                  valueListenable: curve,
                  builder: (_, value, _) => ExtractionChart(
                    curve: value,
                    live: true,
                    height: 240,
                    replayable: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      SchedulerBinding.instance.addTimingsCallback(collect);
      final start = developer.Timeline.now;
      final cpu = processCpuTicks();
      for (var update = 1; update <= 100; update++) {
        curve.value = _curve(points + update);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      final end = developer.Timeline.now;
      final cpuEnd = processCpuTicks();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final frames = collected.where((frame) {
        final time = frame.timestampInMicroseconds(FramePhase.vsyncStart);
        return time >= start && time <= end;
      }).toList();
      final build = frames
          .map((f) => f.buildDuration.inMicroseconds / 1000)
          .toList();
      final raster = frames
          .map((f) => f.rasterDuration.inMicroseconds / 1000)
          .toList();
      expect(frames, isNotEmpty);
      final hz = tester.view.display.refreshRate;
      record({
        'operation': 'live_chart',
        'initialPoints': points,
        'updates': 100,
        'pacingMs': 50,
        'elapsedMs': (end - start) / 1000,
        'refreshHz': hz,
        'frames': frames.length,
        'build': distribution(build)..remove('samples'),
        'raster': distribution(raster)..remove('samples'),
        'buildOverBudget': build.where((ms) => ms > 1000 / hz).length,
        'rasterOverBudget': raster.where((ms) => ms > 1000 / hz).length,
        if (cpu != null && cpuEnd != null) 'processCpuTicks': cpuEnd - cpu,
        ...await memorySnapshot(memory),
      });
      expect(tester.takeException(), isNull);
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(collect);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      curve.dispose();
    }
  }
}

ShotCurve _curve(int count) => ShotCurve(
  timesMs: [for (var i = 0; i < count; i++) i * 100],
  pressure: [for (var i = 0; i < count; i++) math.min(9.0, i / 10)],
  flow: [for (var i = 0; i < count; i++) 1.2 + math.sin(i / 10) * 0.2],
  weight: [for (var i = 0; i < count; i++) i * 0.12],
);
