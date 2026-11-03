import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/manual_pour_run.dart';
import 'package:holybeans/domain/pour_plan.dart';

void main() {
  PourPlan plan({List<BloomStep> blooms = const []}) => PourPlan(
    doseGrams: 15,
    ratio: 16,
    pourIntervalSeconds: 20,
    blooms: blooms,
  );

  for (final started in [15000, 30000]) {
    test('next reminder follows actual start at $started ms', () {
      final run = ManualPourRun(plan());
      expect(run.current!.number, 1);
      expect(run.remainingSeconds(120000), 0);
      expect(run.current!.number, 1);
      run.advance(started);
      expect(run.current!.number, 2);
      expect(run.remainingSeconds(started), 20);
      expect(run.remainingSeconds(started + 19999), 1);
      expect(run.remainingSeconds(started + 20000), 0);
      expect(run.current!.number, 2);
    });
  }
  test('blooms retain their own waits and final pour waits for drawdown', () {
    final run = ManualPourRun(
      plan(
        blooms: const [
          BloomStep(doseMultiple: 2, waitSeconds: 45),
          BloomStep(doseMultiple: 1, waitSeconds: 30),
        ],
      ),
    );
    expect(run.remainingSeconds(0), 45);
    run.advance(15000);
    expect(run.current!.kind, PourStepKind.bloom);
    expect(run.remainingSeconds(15000), 30);
    run.advance(30000);
    expect(run.current!.kind, PourStepKind.pour);
    expect(run.remainingSeconds(30000), 20);
    run.advance(50000);
    run.advance(70000);
    expect(run.current!.number, 3);
    expect(run.remainingSeconds(999999), isNull);
    expect(run.draining, isFalse);
    run.advance(100000);
    expect(run.draining, isTrue);
    expect(run.cueAt(999999), isNull);
    run.advance(999999);
    expect(run.current, isNull);
  });
  test('reminders never replay missed countdowns or repeat while overdue', () {
    final run = ManualPourRun(plan());
    expect(run.cueAt(17000), PourCue.short);
    expect(run.cueAt(17200), isNull);
    expect(run.cueAt(18000), PourCue.short);
    expect(run.cueAt(30000), PourCue.long);
    expect(run.cueAt(31000), isNull);
    expect(run.cueAt(60000), isNull);
    run.advance(60500);
    expect(run.cueAt(77500), PourCue.short);
    expect(run.cueAt(80500), PourCue.long);
  });
}
