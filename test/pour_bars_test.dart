import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_bars.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'bars follow water, allow manual review and resume at 320px $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final plan = PourPlan.standard(15).copyWith(pours: 10);
        double? grams = 180;
        var second = 0;
        late StateSetter refresh;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return Scaffold(
                  body: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: SingleChildScrollView(
                      child: PourBars(plan: plan, second: second, grams: grams),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byKey(const ValueKey('pour-bars-scroll'));
        void visible(int index) {
          final viewport = tester.getRect(scroll);
          final bar = tester.getRect(find.byKey(ValueKey('pour-bar-$index')));
          expect(bar.left, greaterThanOrEqualTo(viewport.left));
          expect(bar.right, lessThanOrEqualTo(viewport.right));
        }

        visible(8);
        await tester.drag(scroll, const Offset(600, 0));
        await tester.pumpAndSettle();
        expect(
          find.text(lookupAppLocalizations(Locale(language)).pourFollow),
          findsOneWidget,
        );
        final before = tester
            .getTopLeft(find.byKey(const ValueKey('pour-bar-0')))
            .dx;
        refresh(() {
          grams = 220;
        });
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('pour-bar-0'))).dx,
          before,
        );
        await tester.tap(find.byKey(const ValueKey('pour-follow')));
        await tester.pumpAndSettle();
        visible(10);
        refresh(() {
          grams = 10;
          second = 250;
        });
        await tester.pumpAndSettle();
        visible(0);
        refresh(() {
          grams = null;
        });
        await tester.pumpAndSettle();
        visible(7);
        expect(
          find.text(lookupAppLocalizations(Locale(language)).pourNoReading),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
