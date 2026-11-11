import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/espresso_chart.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/espresso_map_page.dart';

import 'helpers/ui_test_support.dart';

void main() {
  test('the ratio suggests the style', () {
    expect(EspressoStyle.forRatio(1.2), EspressoStyle.ristretto);
    expect(EspressoStyle.forRatio(1.66), EspressoStyle.ristretto);
    expect(EspressoStyle.forRatio(1.67), EspressoStyle.ristretto);
    expect(EspressoStyle.forRatio(1.999999), EspressoStyle.ristretto);
    expect(EspressoStyle.forRatio(2.0), EspressoStyle.normale);
    expect(EspressoStyle.forRatio(2.5), EspressoStyle.normale);
    expect(EspressoStyle.forRatio(2.6), EspressoStyle.normale);
    expect(EspressoStyle.forRatio(2.999999), EspressoStyle.normale);
    expect(EspressoStyle.forRatio(3), EspressoStyle.lungo);
    expect(EspressoStyle.forRatio(3.000001), EspressoStyle.lungo);
    expect(EspressoStyle.forRatio(4), EspressoStyle.lungo);
  });

  test('axes keep the target box in the middle third', () {
    expect(EspressoStyle.normale.eyAxis, (min: 14.0, max: 26.0));
    expect(EspressoStyle.normale.tdsAxis, (min: 4.0, max: 16.0));
    expect(EspressoStyle.ristretto.tdsAxis, (min: 6.0, max: 24.0));
    expect(EspressoStyle.lungo.tdsAxis, (min: 2.0, max: 11.0));
  });

  test('the position is neutral: low, within or high', () {
    expect(
      espressoPosition(
        style: EspressoStyle.normale,
        eyPercent: 19.66,
        tdsPercent: 8.66,
      ),
      (ey: RangePosition.within, tds: RangePosition.within),
    );
    expect(
      espressoPosition(
        style: EspressoStyle.ristretto,
        eyPercent: 23,
        tdsPercent: 8.66,
      ),
      (ey: RangePosition.high, tds: RangePosition.low),
    );
  });

  Future<void> show(
    WidgetTester tester, {
    required double ey,
    required double tds,
    required double ratio,
  }) => tester.pumpWidget(
    localizedApp(
      locale: const Locale('en'),
      home: EspressoMapPage(eyPercent: ey, tdsPercent: tds, ratio: ratio),
    ),
  );

  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('espresso-summary'))).data!;

  testWidgets('a shot is placed against the style its ratio suggests', (
    tester,
  ) async {
    await show(tester, ey: 19.66, tds: 8.66, ratio: 19.66 / 8.66);
    expect(
      find.text('Suggested style for ratio 1:2.27: Normale'),
      findsOneWidget,
    );
    expect(summary(tester), 'Within Normale');
    expect(find.text('EY 19.66 %, TDS 8.66 %, 1:2.27'), findsOneWidget);
    // Another style can be chosen by hand.
    await tester.tap(find.byKey(const ValueKey('espresso-style-ristretto')));
    await tester.pump();
    expect(summary(tester), 'Extraction in range, Low TDS');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shot beyond the axes says so instead of a marker', (
    tester,
  ) async {
    await show(tester, ey: 30, tds: 20, ratio: 1.5);
    expect(summary(tester), 'High extraction, High TDS, Off the chart');
  });
  for (final language in ['es', 'en']) {
    testWidgets('ratio rounding preserves the suggested style ($language)', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = Locale(language);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      for (final (ratio, style, displayed) in [
        (1.99, EspressoStyle.ristretto, '1:1.99'),
        (1.999, EspressoStyle.ristretto, '<1:2'),
        (2.0, EspressoStyle.normale, '1:2'),
        (2.511, EspressoStyle.normale, '1:2.51'),
        (2.5498, EspressoStyle.normale, '1:2.55'),
        (2.99, EspressoStyle.normale, '1:2.99'),
        (2.999999, EspressoStyle.normale, '<1:3'),
        (3.0, EspressoStyle.lungo, '1:3'),
        (3.001, EspressoStyle.lungo, '1:3'),
      ]) {
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: EspressoMapPage(
              eyPercent: 20,
              tdsPercent: 20 / ratio,
              ratio: ratio,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(EspressoMapContent)),
        )!;
        final localizedRatio = language == 'es'
            ? displayed.replaceAll('.', ',')
            : displayed;
        expect(
          find.text(
            strings.espressoStyleByRatio(
              espressoStyleName(strings, style),
              localizedRatio,
            ),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(ValueKey('espresso-style-${style.name}')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('espresso-values')))
              .data,
          endsWith(localizedRatio),
        );
        final semantics = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape('$localizedRatio. '))),
          findsOneWidget,
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'reported shots suggest normale and keep TDS targets ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.localeTestValue = Locale(language);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: EspressoMapContent(
                  eyPercent: 18.53,
                  tdsPercent: 7.38,
                  ratio: 18.53 / 7.38,
                  other: (
                    eyPercent: 17.9,
                    tdsPercent: 7.02,
                    ratio: 17.9 / 7.02,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(EspressoMapContent)),
        )!;
        final a = language == 'es' ? '1:2,51' : '1:2.51';
        final b = language == 'es' ? '1:2,55' : '1:2.55';
        expect(
          find.text(
            'A: ${strings.espressoStyleByRatio(strings.espressoNormale, a)}\n'
            'B: ${strings.espressoStyleByRatio(strings.espressoNormale, b)}',
          ),
          findsOneWidget,
        );
        String shotSummary(String letter) => tester
            .widget<Text>(find.byKey(ValueKey('espresso-summary-$letter')))
            .data!;
        expect(
          shotSummary('a'),
          '${strings.espressoEyWithin}, ${strings.espressoTdsLow}',
        );
        expect(
          shotSummary('b'),
          '${strings.espressoEyLow}, ${strings.espressoTdsLow}',
        );
        await tester.tap(find.byKey(const ValueKey('espresso-style-lungo')));
        await tester.pumpAndSettle();
        expect(shotSummary('a'), strings.espressoWithin(strings.espressoLungo));
        expect(
          shotSummary('b'),
          '${strings.espressoEyLow}, ${strings.espressoTdsWithin}',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'comparison shares axes across styles and identifies both shots ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        Future<void> showComparison(EspressoMapPoint other) async {
          await tester.pumpWidget(
            localizedApp(
              locale: Locale(language),
              theme: ThemeData(
                brightness: language == 'es'
                    ? Brightness.dark
                    : Brightness.light,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: EspressoMapContent(
                    eyPercent: 21,
                    tdsPercent: 15,
                    ratio: 1.4,
                    other: other,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await showComparison((eyPercent: 20, tdsPercent: 5, ratio: 4));
        final offChart = language == 'en'
            ? 'Off the chart'
            : 'Fuera de la gráfica';
        expect(find.textContaining(offChart), findsNothing);
        final semantics = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp(r'A: EY 21.*B: EY 20')),
          findsOneWidget,
        );
        semantics.dispose();
        await tester.tap(find.byKey(const ValueKey('espresso-style-lungo')));
        await tester.pumpAndSettle();
        expect(find.textContaining(offChart), findsNothing);
        // Coincident shots keep both identities, and B updates independently.
        await showComparison((eyPercent: 21, tdsPercent: 15, ratio: 1.4));
        expect(find.text('A: EY 21 %, TDS 15 %, 1:1.4'), findsOneWidget);
        expect(find.text('B: EY 21 %, TDS 15 %, 1:1.4'), findsOneWidget);
        await showComparison((eyPercent: 30, tdsPercent: 10, ratio: 3));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('espresso-summary-b')))
              .data,
          contains(offChart),
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('espresso-summary-a')))
              .data,
          isNot(contains(offChart)),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
