import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/ui/brews/filter_brew_readout.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'Spanish large text and unknown or exceeded targets remain readable',
    (tester) async {
      Future<void> show(
        FilterBrewProgress progress, {
        bool showRatio = true,
      }) async {
        await tester.pumpWidget(
          localizedApp(
            locale: const Locale('es'),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.5),
                    ),
                    child: FilterBrewReadout(
                      progress: progress,
                      showRatio: showRatio,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await show(
        FilterBrewProgress(
          pouredGrams: 281,
          doseGrams: 18,
          targetWaterGrams: 300,
        ),
      );
      expect(find.text('281 g'), findsOneWidget);
      expect(find.text('1:15.6'), findsOneWidget);
      expect(find.text('1:16.7'), findsOneWidget);
      expect(find.text('19 g'), findsOneWidget);
      await show(
        FilterBrewProgress(
          pouredGrams: 310,
          doseGrams: 20,
          targetWaterGrams: 300,
        ),
      );
      expect(find.text('Agua de más'), findsOneWidget);
      expect(find.text('10 g'), findsOneWidget);
      await show(FilterBrewProgress(pouredGrams: 281));
      expect(find.text('—'), findsNWidgets(3));
      await show(
        FilterBrewProgress(pouredGrams: 281, targetWaterGrams: 300),
        showRatio: false,
      );
      expect(find.text('Ratio actual'), findsNothing);
      expect(find.text('Ratio objetivo'), findsNothing);
    },
  );
}
