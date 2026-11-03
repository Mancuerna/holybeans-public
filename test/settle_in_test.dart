import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/settle_in.dart';

void main() {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

  Widget settle(int createdAtMs) => SettleIn(
    id: 'brew',
    createdAtMs: createdAtMs,
    builder: (context, reveal, fill) => Text(
      '${reveal.toStringAsFixed(2)} ${fill.toStringAsFixed(2)}',
      textDirection: TextDirection.ltr,
    ),
  );

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text, skipOffstage: false)).data!;

  testWidgets('a brew just saved opens and runs up to its figures', (
    tester,
  ) async {
    await tester.pumpWidget(settle(nowMs));
    expect(shown(tester), '0.00 0.00');
    // Past the opening, the figures are still running.
    await tester.pump(const Duration(milliseconds: 800));
    final [reveal, fill] = shown(tester).split(' ').map(double.parse).toList();
    expect(reveal, 1);
    expect(fill, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(shown(tester), '1.00 1.00');
  });

  testWidgets('older brews, reduced motion and hidden tabs stay still', (
    tester,
  ) async {
    await tester.pumpWidget(settle(nowMs - 60000));
    expect(shown(tester), '1.00 1.00');

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: settle(nowMs),
      ),
    );
    expect(shown(tester), '1.00 1.00');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: IndexedStack(children: [const SizedBox.shrink(), settle(nowMs)]),
      ),
    );
    expect(shown(tester), '1.00 1.00');
  });

  test('a running figure keeps the decimals of where it stops', () {
    expect(settledShare(250, 0.75), 188);
    expect(settledShare(299.1, 0.5), 149.6);
    expect(settledShare(250, 1), 250);
  });

  testWidgets('a running figure keeps the width it will settle at', (
    tester,
  ) async {
    Future<double> widthOf(String text) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SteadyText(text, settled: '250 / 250 g')),
        ),
      );
      return tester.getSize(find.byType(SteadyText)).width;
    }

    final settled = await widthOf('250 / 250 g');
    expect(await widthOf('0 / 250 g'), settled);
    expect(await widthOf('88 / 250 g'), settled);
  });
}
