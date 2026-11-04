import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/lazy_indexed_stack.dart';

void main() {
  testWidgets(
    'unvisited tabs stay unmounted and visited tabs keep current data and state',
    (tester) async {
      final builds = [0, 0];
      Widget app(int selected, String value) => MaterialApp(
        home: Material(
          child: LazyIndexedStack(
            index: selected,
            children: [
              for (var i = 0; i < 2; i++)
                Builder(
                  builder: (_) {
                    builds[i]++;
                    return Column(
                      children: [Text('$i $value'), const TextField()],
                    );
                  },
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app(0, 'first'));
      expect(builds, [1, 0]);
      await tester.enterText(find.byType(TextField), 'kept');
      await tester.pumpWidget(app(1, 'second'));
      expect(builds, [2, 1]);
      await tester.pumpWidget(app(1, 'third'));
      expect(builds, [3, 2]);
      await tester.pumpWidget(app(0, 'latest'));
      expect(builds, [4, 3]);
      expect(find.text('0 latest'), findsOneWidget);
      expect(find.text('kept'), findsOneWidget);
    },
  );
}
