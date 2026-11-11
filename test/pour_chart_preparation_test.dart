import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_chart.dart';

import 'helpers/ui_test_support.dart';

class _CountedPlan extends PourPlan {
  _CountedPlan({double dose = 18})
    : super(
        doseGrams: dose,
        ratio: 16,
        blooms: const [BloomStep(doseMultiple: 2, waitSeconds: 45)],
      );
  int reads = 0;
  @override
  List<PourStep> get steps {
    reads++;
    return super.steps;
  }
}

void main() {
  testWidgets(
    'pour chart prepares steps once per paint and guards invalid plans',
    (tester) async {
      var plan = _CountedPlan();
      final elapsed = ValueNotifier<double?>(null);
      addTearDown(elapsed.dispose);
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: elapsed,
              builder: (_, value, _) =>
                  PourChart(plan: plan, elapsedSeconds: value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      plan.reads = 0;
      for (var i = 0; i < 100; i++) {
        elapsed.value = i.toDouble();
        await tester.pump();
      }
      final measured = plan.reads;
      stdout.writeln('POUR_STEP_PREPARATIONS $measured');
      plan = _CountedPlan(dose: 0);
      elapsed.value = 101;
      await tester.pump();
      expect(plan.reads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(measured, 100);
    },
  );
}
