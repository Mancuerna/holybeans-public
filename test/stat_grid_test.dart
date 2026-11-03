import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';

void main() {
  // A phone with larger system text and display size, like the POCO X7 Pro
  // where "Temperature" split as "Temperatu / re".
  testWidgets('tile labels wrap between words, never inside one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.45)),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: StatGrid(
                items: [
                  StatItem('Dose', '17 g'),
                  StatItem('Temperature', '90 °C'),
                  StatItem('Preinfusion time', '8 s'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    double height(String label) =>
        tester.renderObject<RenderParagraph>(find.text(label)).size.height;
    double width(String label) =>
        tester.renderObject<RenderParagraph>(find.text(label)).size.width;
    final oneLine = height('Dose');
    // Still three columns, and the long word stays whole on one line.
    expect(width('Temperature'), lessThan(110));
    expect(height('Temperature'), lessThanOrEqualTo(oneLine));
    // Two words may take two lines.
    expect(height('Preinfusion time'), lessThanOrEqualTo(oneLine * 2.1));
    expect(tester.takeException(), isNull);
  });
}
