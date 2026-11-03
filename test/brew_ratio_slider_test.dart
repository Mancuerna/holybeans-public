import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_ratio_slider.dart';
import 'package:holybeans/ui/brews/espresso_brew_readout.dart';

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets('ratio steps, bounds and live target at 320 px in $locale', (
      tester,
    ) async {
      var value = 2.0;
      var dose = 17.0;
      var espresso = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuild = setState;
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            BrewRatioSlider(
                              espresso: espresso,
                              doseGrams: dose,
                              ratio: value,
                              onChanged: (next) => setState(() => value = next),
                            ),
                            EspressoBrewReadout(
                              grams: 20,
                              doseGrams: dose,
                              targetGrams: dose * value,
                              targetRatio: value,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final plus = find.byKey(const ValueKey('brew-ratio-increase'));
      final minus = find.byKey(const ValueKey('brew-ratio-decrease'));
      await tester.tap(plus);
      await tester.pump();
      expect(value, closeTo(2.1, 0.0001));
      await tester.tap(minus);
      await tester.pump();
      expect(value, 2);
      rebuild(() {
        value = 2.3;
        dose = 17;
      });
      await tester.pump();
      expect(find.textContaining('39.1 g'), findsNWidgets(2));
      rebuild(() => dose = 20);
      await tester.pump();
      expect(find.textContaining('46 g'), findsNWidgets(2));
      rebuild(() => value = 10);
      await tester.pump();
      expect(tester.widget<IconButton>(plus).onPressed, isNull);
      rebuild(() => value = 1);
      await tester.pump();
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
      rebuild(() {
        espresso = false;
        value = 16;
      });
      await tester.pump();
      await tester.tap(plus);
      await tester.pump();
      expect(value, 16.5);
      rebuild(() => value = 22);
      await tester.pump();
      final filterSlider = tester.widget<Slider>(find.byType(Slider));
      expect(filterSlider.value, 20);
      expect(filterSlider.max, 20);
      expect(filterSlider.onChanged, isNull);
      expect(filterSlider.semanticFormatterCallback!(20), contains('1:22'));
      await tester.tap(minus);
      await tester.pump();
      expect(value, 21.5);
      await tester.tap(plus);
      await tester.pump();
      expect(value, 22);
      rebuild(() => value = 20.5);
      await tester.pump();
      await tester.tap(minus);
      await tester.pump();
      expect(value, 20);
      expect(tester.widget<IconButton>(plus).onPressed, isNotNull);
      await tester.tap(plus);
      await tester.pump();
      expect(value, 20.5);
      rebuild(() => value = 2599 / 18);
      await tester.pump();
      final extremeSlider = tester.widget<Slider>(find.byType(Slider));
      expect(extremeSlider.value, 20);
      expect(extremeSlider.max, 20);
      expect(extremeSlider.onChanged, isNull);
      await tester.tap(minus);
      await tester.pump();
      expect(value, closeTo(144, 0.0001));
      await tester.tap(plus);
      await tester.pump();
      expect(value, closeTo(144.5, 0.0001));
      // Filter water is its own field, so the slider does not repeat it.
      expect(find.byKey(const ValueKey('brew-ratio-target')), findsNothing);
      rebuild(() => dose = 0);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
