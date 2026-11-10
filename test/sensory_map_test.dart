import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/sensory_map_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'detail opens the localized sensory map at the recorded EY and TDS',
    (tester) async {
      final database = memoryDatabase();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(database.close);

      final repository = JournalRepository(database);
      final measuredCoffee = await repository.createCoffee(
        name: 'Con TDS',
        roaster: 'Test roaster',
      );
      await repository.createBrew(
        coffeeId: measuredCoffee,
        methodName: 'V60',
        doseGrams: 18,
        beverageGrams: 258,
        tdsPercent: 1.35,
        brewedAt: DateTime(2026, 9, 28, 12),
      );
      final missingEyCoffee = await repository.createCoffee(
        name: 'Sin EY',
        roaster: 'Test roaster',
      );
      await repository.createBrew(
        coffeeId: missingEyCoffee,
        methodName: 'V60',
        doseGrams: 18,
        beverageGrams: 258,
        brewedAt: DateTime(2026, 9, 28, 13),
      );
      final outsideRangeCoffee = await repository.createCoffee(
        name: 'Fuera del rango',
        roaster: 'Test roaster',
      );
      await repository.createBrew(
        coffeeId: outsideRangeCoffee,
        methodName: 'V60',
        doseGrams: 18,
        beverageGrams: 400,
        tdsPercent: 1.35,
        brewedAt: DateTime(2026, 9, 28, 14),
      );
      final outsideTdsCoffee = await repository.createCoffee(
        name: 'TDS fuera del rango',
        roaster: 'Test roaster',
      );
      await repository.createBrew(
        coffeeId: outsideTdsCoffee,
        methodName: 'V60',
        doseGrams: 18,
        beverageGrams: 200,
        tdsPercent: 1.7,
        brewedAt: DateTime(2026, 9, 28, 15),
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('es')),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 2);

      final measuredBrew = find.text('Con TDS');
      await tester.scrollUntilVisible(
        measuredBrew,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(measuredBrew);
      await tester.pumpAndSettle();
      final mapButton = find.byKey(const ValueKey('open-sensory-map-button'));
      expect(mapButton, findsOneWidget);
      await tester.ensureVisible(mapButton);
      await tester.tap(mapButton);
      await tester.pumpAndSettle();

      expect(find.byType(SensoryMapPage), findsOneWidget);
      expect(find.text('Mapa sensorial'), findsOneWidget);
      expect(
        find.text('Leer el artículo (DOI 10.1111/1750-3841.16531)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sensory-map-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('sensory-map-values')), findsNothing);
      expect(find.textContaining('Guinard et al.'), findsNothing);
      expect(find.textContaining('no predicen'), findsNothing);
      expect(find.textContaining('norte de California'), findsNothing);
      expect(find.text('Sensación más dulce'), findsOneWidget);
      final plotRect = tester.getRect(
        find.byKey(const ValueKey('sensory-map-plot-area')),
      );
      for (final labelKey in [
        'sensory-map-trend-citrus',
        'sensory-map-trend-roasty',
        'sensory-map-trend-sweet',
        'sensory-map-trend-tea',
      ]) {
        final labelRect = tester.getRect(find.byKey(ValueKey(labelKey)));
        expect(labelRect.left, greaterThanOrEqualTo(plotRect.left));
        expect(labelRect.top, greaterThanOrEqualTo(plotRect.top));
        expect(labelRect.right, lessThanOrEqualTo(plotRect.right));
        expect(labelRect.bottom, lessThanOrEqualTo(plotRect.bottom));
      }
      expect(
        tester
            .getRect(find.byKey(const ValueKey('sensory-map-trend-sweet')))
            .bottom,
        lessThan(plotRect.bottom),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('sensory-map-trend-tea')))
            .bottom,
        lessThan(plotRect.bottom),
      );
      final marker = find.byKey(const ValueKey('sensory-map-marker'));
      expect(marker, findsOneWidget);
      final pointValues = find.byKey(
        const ValueKey('sensory-map-point-values'),
      );
      expect(pointValues, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sensory-map-chart')),
          matching: find.text('EY 19.35%'),
        ),
        findsOneWidget,
      );
      expect(find.text('TDS 1.35%'), findsOneWidget);
      final markerSemantics = tester.widget<Semantics>(marker);
      expect(markerSemantics.properties.label, contains('19.35%'));
      expect(markerSemantics.properties.label, contains('1.35%'));

      final chartRect = tester.getRect(
        find.byKey(const ValueKey('sensory-map-chart')),
      );
      final markerRect = tester.getRect(marker);
      final pointValuesRect = tester.getRect(pointValues);
      final plot = Rect.fromLTRB(
        chartRect.left + 48,
        chartRect.top + 30,
        chartRect.right - 14,
        chartRect.bottom - 54,
      );
      expect(pointValuesRect.left, greaterThanOrEqualTo(plot.left));
      expect(pointValuesRect.top, greaterThanOrEqualTo(plot.top));
      expect(pointValuesRect.right, lessThanOrEqualTo(plot.right));
      expect(pointValuesRect.bottom, lessThanOrEqualTo(plot.bottom));
      expect(pointValuesRect.overlaps(markerRect), isFalse);
      final expectedMarker = Offset(
        plot.left + (19.35 - 14) / (26 - 14) * plot.width,
        plot.bottom - (1.35 - 0.8) / (1.6 - 0.8) * plot.height,
      );
      expect(markerRect.center.dx, closeTo(expectedMarker.dx, 1));
      expect(markerRect.center.dy, closeTo(expectedMarker.dy, 1));

      await _popCurrentRoute(tester, find.byType(SensoryMapPage));
      await _popCurrentRoute(tester, find.byType(BottomSheet));
      await tester.tap(find.text('Sin EY'));
      await tester.pumpAndSettle();
      expect(mapButton, findsNothing);

      await _popCurrentRoute(tester, find.byType(BottomSheet));
      await tester.tap(find.text('Fuera del rango'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(mapButton);
      await tester.tap(mapButton);
      await tester.pumpAndSettle();
      expect(find.text('Fuera de rango'), findsOneWidget);
      expect(find.byKey(const ValueKey('sensory-map-marker')), findsNothing);
      expect(
        find.byKey(const ValueKey('sensory-map-point-values')),
        findsNothing,
      );
      final outOfRangeAnnotation = tester.widget<Semantics>(
        find.byKey(const ValueKey('sensory-map-out-of-range')),
      );
      expect(outOfRangeAnnotation.properties.label, contains('EY 30%'));
      expect(outOfRangeAnnotation.properties.label, contains('TDS 1.35%'));
      expect(outOfRangeAnnotation.properties.label, contains('Fuera de rango'));
      final outOfRangePlot = tester.getRect(
        find.byKey(const ValueKey('sensory-map-plot-area')),
      );
      final annotationRect = tester.getRect(
        find.byKey(const ValueKey('sensory-map-out-of-range')),
      );
      expect(annotationRect.left, greaterThanOrEqualTo(outOfRangePlot.left));
      expect(annotationRect.top, greaterThanOrEqualTo(outOfRangePlot.top));
      expect(annotationRect.right, lessThanOrEqualTo(outOfRangePlot.right));
      expect(annotationRect.bottom, lessThanOrEqualTo(outOfRangePlot.bottom));
      expect(tester.takeException(), isNull);

      await _popCurrentRoute(tester, find.byType(SensoryMapPage));
      await _popCurrentRoute(tester, find.byType(BottomSheet));
      final tdsOutOfRangeBrew = find.text('TDS fuera del rango');
      await tester.scrollUntilVisible(
        tdsOutOfRangeBrew,
        -160,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(tdsOutOfRangeBrew);
      await tester.pumpAndSettle();
      await tester.ensureVisible(mapButton);
      await tester.tap(mapButton);
      await tester.pumpAndSettle();
      final outOfTdsAnnotation = tester.widget<Semantics>(
        find.byKey(const ValueKey('sensory-map-out-of-range')),
      );
      expect(outOfTdsAnnotation.properties.label, contains('EY 18.89%'));
      expect(outOfTdsAnnotation.properties.label, contains('TDS 1.7%'));
      expect(find.byKey(const ValueKey('sensory-map-marker')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('comparison chart draws both measured points', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(
        home: const SensoryMapChart(
          eyPercent: 18.15,
          tdsPercent: 1.37,
          otherEyPercent: 16.86,
          otherTdsPercent: 1.29,
        ),
      ),
    );
    final a = find.byKey(const ValueKey('sensory-map-marker-a'));
    final b = find.byKey(const ValueKey('sensory-map-marker-b'));
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(
      find.byKey(const ValueKey('sensory-map-point-values')),
      findsNothing,
    );
    final chartRect = tester.getRect(
      find.byKey(const ValueKey('sensory-map-chart')),
    );
    final plot = Rect.fromLTRB(
      chartRect.left + 48,
      chartRect.top + 30,
      chartRect.right - 14,
      chartRect.top + chartRect.width / 1.08 - 54,
    );
    Offset expected(double ey, double tds) => Offset(
      plot.left + (ey - 14) / 12 * plot.width,
      plot.bottom - (tds - 0.8) / 0.8 * plot.height,
    );
    expect(tester.getRect(a).center.dx, closeTo(expected(18.15, 1.37).dx, 1));
    expect(tester.getRect(a).center.dy, closeTo(expected(18.15, 1.37).dy, 1));
    expect(tester.getRect(b).center.dx, closeTo(expected(16.86, 1.29).dx, 1));
    expect(tester.getRect(b).center.dy, closeTo(expected(16.86, 1.29).dy, 1));
  });
}

Future<void> _popCurrentRoute(WidgetTester tester, Finder routeContent) async {
  Navigator.of(tester.element(routeContent)).pop();
  await tester.pumpAndSettle();
}
