import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/motion.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('motion duration respects reduced motion: $reduced', (
      tester,
    ) async {
      const requested = Duration(milliseconds: 240);
      late Duration result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Builder(
            builder: (context) {
              result = motionDuration(context, requested);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(result, reduced ? Duration.zero : requested);
    });
  }
}
