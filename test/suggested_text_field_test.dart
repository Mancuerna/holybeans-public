import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/suggested_text_field.dart';

void main() {
  for (final above in [false, true]) {
    testWidgets(
      'suggestions ${above ? 'above the keyboard' : 'below the field'} remain selectable',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.only(top: above ? 430 : 50),
                child: SuggestedTextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Profile'),
                  suggestions: const [
                    'Plano sin preinfusión',
                    'Plano con preinfusión',
                  ],
                  suggestionsAbove: above,
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextFormField), 'pla');
        await tester.pumpAndSettle();
        final second = find.text('Plano con preinfusión');
        expect(second.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(second).dy, lessThan(544));
        if (above) {
          expect(
            tester.getBottomRight(second).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.byType(TextFormField)).dy),
          );
        } else {
          expect(
            tester.getTopLeft(second).dy,
            greaterThan(tester.getBottomRight(find.byType(TextFormField)).dy),
          );
        }
        await tester.tap(second);
        await tester.pumpAndSettle();
        expect(controller.text, 'Plano con preinfusión');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
