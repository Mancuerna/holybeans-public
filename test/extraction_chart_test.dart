import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/curve_legend_button.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/extraction_readout.dart';

import 'helpers/ui_test_support.dart';

void main() {
  final curve = ShotCurve(
    timesMs: const [0, 10000, 10100, 20000, 39200],
    pressure: const [0, 4.3, 7.2, 4.7, 0],
    flow: const [0, 10.4, 10.4, 1.2, 0],
    weight: const [0, 5, 5.1, 25, 42],
  );

  Future<void> show(
    WidgetTester tester, {
    required String locale,
    double width = 320,
    ShotCurve? drawn,
    bool showFlowStatistics = true,
    bool interactive = true,
  }) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: SingleChildScrollView(
                  child: ExtractionChart(
                    curve: drawn ?? curve,
                    interactive: interactive,
                    flowUnit: 'g/s',
                    firstDripMs: 4000,
                    showFlowStatistics: showFlowStatistics,
                    targetWeightGrams: 39.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleWithWorkers(tester);
  }

  String value(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .join(' ');

  Finder plotFinder() => find
      .descendant(
        of: find.byKey(const ValueKey('extraction-chart')),
        matching: find.byType(CustomPaint),
      )
      .last;

  _MarkerCanvas paintChart(WidgetTester tester) {
    final plot = plotFinder();
    final canvas = _MarkerCanvas();
    tester
        .widget<CustomPaint>(plot)
        .painter!
        .paint(canvas, tester.getSize(plot));
    return canvas;
  }

  testWidgets('shared peak marker sits on the curve and retains recorded max', (
    tester,
  ) async {
    await show(tester, locale: 'en', interactive: false);
    final canvas = paintChart(tester);
    expect(canvas.markers, hasLength(1));
    canvas.expectMarkersOnLines();
    expect(value(tester, 'curve-pressure-value'), contains('7.2 bar'));
  });

  testWidgets('cursor markers follow segments between irregular samples', (
    tester,
  ) async {
    await show(tester, locale: 'en');
    final rect = tester.getRect(plotFinder());
    // Well between recorded samples, rather than exactly on a timestamp.
    await tester.tapAt(rect.topLeft + const Offset(160, 100));
    await tester.pump();
    final canvas = paintChart(tester);
    expect(canvas.markers, hasLength(4));
    canvas.expectMarkersOnLines();
  });

  testWidgets('markers follow the reduced display curve for large recordings', (
    tester,
  ) async {
    final recorded = ShotCurve(
      timesMs: [for (var i = 0; i < 1500; i++) i * 100],
      pressure: [for (var i = 0; i < 1500; i++) i == 750 ? 9.0 : 2.0],
      flow: [for (var i = 0; i < 1500; i++) (i % 17).toDouble()],
      weight: [for (var i = 0; i < 1500; i++) i * 0.1],
    );
    await show(tester, locale: 'en', drawn: recorded);
    expect(value(tester, 'curve-pressure-value'), contains('9.0 bar'));
    paintChart(tester).expectMarkersOnLines();
    final rect = tester.getRect(plotFinder());
    await tester.tapAt(rect.topLeft + const Offset(163, 100));
    await tester.pump();
    final canvas = paintChart(tester);
    expect(canvas.markers, hasLength(4));
    canvas.expectMarkersOnLines();
  });

  testWidgets(
    'large curves finish real worker preparation and retain every readout sample',
    (tester) async {
      final recorded = ShotCurve(
        timesMs: [for (var i = 0; i < 1500; i++) i * 100],
        flow: [for (var i = 0; i < 1500; i++) 1.0],
        weight: [for (var i = 0; i < 1500; i++) i * 0.1],
      );
      await show(tester, locale: 'en', drawn: recorded);
      expect(find.byKey(const ValueKey('curve-preparing')), findsNothing);
      final readout = tester.widget<ExtractionReadout>(
        find.byType(ExtractionReadout),
      );
      expect(readout.curve.timesMs, recorded.timesMs);
      expect(readout.shown.timesMs, recorded.timesMs);
      expect(readout.curve.weight, recorded.weight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filter retains maximum and cursor but hides flow statistics', (
    tester,
  ) async {
    await show(tester, locale: 'en', showFlowStatistics: false);
    expect(find.byKey(const ValueKey('curve-flow-value')), findsOneWidget);
    expect(find.byKey(const ValueKey('curve-flow-mean')), findsNothing);
    expect(find.byKey(const ValueKey('curve-flow-median')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a knock on the scale at the end does not set the flow peak', (
    tester,
  ) async {
    // Four pours of about 15 g/s, then the scale is knocked as the brew
    // ends: one reading jumps 28 g and comes back.
    final times = [for (var i = 0; i < 100; i++) i * 200];
    final flow = [
      for (var i = 0; i < 100; i++) i % 25 < 4 ? 15.0 + i % 25 : 0.0,
    ]..[98] = 98.5;
    final weight = [for (var i = 0; i < 100; i++) 50.0 + i];
    weight[98] = 175;
    await show(
      tester,
      locale: 'en',
      showFlowStatistics: false,
      drawn: ShotCurve(timesMs: times, flow: flow, weight: weight),
    );
    expect(value(tester, 'curve-flow-value'), contains('18.0'));
    expect(value(tester, 'curve-flow-value'), isNot(contains('98.5')));
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['es', 'en']) {
    testWidgets(
      'compact legend and grouped statistics below plot at 320 px in $locale',
      (tester) async {
        await show(tester, locale: locale);
        final chart = find.byKey(const ValueKey('extraction-chart'));
        final readout = find.byKey(const ValueKey('curve-readout'));
        final plot = find
            .descendant(of: chart, matching: find.byType(CustomPaint))
            .last;
        expect(
          tester.getRect(readout).top,
          greaterThan(tester.getRect(plot).bottom),
        );
        expect(find.byType(FilterChip), findsNothing);
        expect(find.byType(CurveLegendButton), findsNWidgets(3));
        for (final series in CurveSeries.values) {
          final button = find.byKey(ValueKey('curve-series-${series.name}'));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
        expect(value(tester, 'curve-pressure-value'), contains('7.2 bar'));
        expect(find.byKey(const ValueKey('curve-duration')), findsNothing);
        expect(find.byKey(const ValueKey('curve-weight-value')), findsNothing);
        expect(
          value(tester, 'curve-flow-mean'),
          contains(locale == 'es' ? 'Media' : 'Mean'),
        );
        expect(
          value(tester, 'curve-flow-median'),
          contains(locale == 'es' ? 'Mediana' : 'Median'),
        );
        expect(
          find.text('Caudal (g/s)').evaluate().isNotEmpty ||
              find.text('Flow (g/s)').evaluate().isNotEmpty,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('curve-series-flow')));
        await tester.pump();
        expect(find.byKey(const ValueKey('curve-flow-mean')), findsNothing);
        expect(
          find.byKey(const ValueKey('curve-pressure-value')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('curve-series-flow')));
        await tester.pump();
        expect(find.byKey(const ValueKey('curve-flow-mean')), findsOneWidget);
      },
    );
  }

  testWidgets(
    'cursor and replay keep full-window statistics while instantaneous values change',
    (tester) async {
      await show(tester, locale: 'en', width: 1000);
      final before = value(tester, 'curve-flow-mean');
      final plot = find
          .descendant(
            of: find.byKey(const ValueKey('extraction-chart')),
            matching: find.byType(CustomPaint),
          )
          .last;
      final rect = tester.getRect(plot);
      await tester.tapAt(rect.centerLeft + Offset(rect.width * 0.3, 0));
      await tester.pump();
      expect(value(tester, 'curve-duration'), contains('0:'));
      expect(find.byKey(const ValueKey('curve-weight-value')), findsOneWidget);
      expect(value(tester, 'curve-pressure-value'), isNot(contains('max')));
      expect(value(tester, 'curve-flow-mean'), before);
      await tester.tap(find.byKey(const ValueKey('curve-replay')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(value(tester, 'curve-flow-mean'), before);
      await tester.pump(const Duration(seconds: 30));
      expect(value(tester, 'curve-pressure-value'), contains('max 7.2 bar'));
      expect(find.byKey(const ValueKey('curve-duration')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a filter curve with pauses omits redundant weight and flow statistics',
    (tester) async {
      // Two short pours with long pauses, then the brewer lifted off.
      final pulses = ShotCurve(
        timesMs: const [0, 5000, 10000, 60000, 65000, 70000, 180000, 181000],
        flow: const [0, 15, -0.001, -0.001, 15, -0.001, -0.001, 0],
        weight: const [0, 50, 100, 100, 250, 300, 300, 100],
      );
      await show(
        tester,
        locale: 'en',
        drawn: pulses,
        showFlowStatistics: false,
      );
      expect(find.byKey(const ValueKey('curve-weight-value')), findsNothing);
      expect(find.byKey(const ValueKey('curve-flow-median')), findsNothing);
      expect(find.byKey(const ValueKey('curve-flow-mean')), findsNothing);
      expect(value(tester, 'curve-flow-value'), contains('15.0'));
      expect(tester.takeException(), isNull);
    },
  );
}

class _MarkerCanvas extends Fake implements Canvas {
  final paths = <Color, Path>{};
  final markers = <({Color color, Offset center})>[];

  @override
  void drawPath(Path path, Paint paint) => paths[paint.color] = path;

  @override
  void drawCircle(Offset center, double radius, Paint paint) {
    markers.add((color: paint.color, center: center));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {}

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {}

  void expectMarkersOnLines() {
    for (final marker in markers) {
      // Inspect the actual painted path, independently of its data source.
      final metrics = paths[marker.color]!.computeMetrics();
      var distance = double.infinity;
      for (final metric in metrics) {
        for (var offset = 0.0; offset <= metric.length; offset += 0.1) {
          final point = metric.getTangentForOffset(offset)!.position;
          final candidate = (point - marker.center).distance;
          if (candidate < distance) distance = candidate;
        }
      }
      expect(distance, lessThan(0.2), reason: 'Marker must lie on its line');
    }
  }
}
