import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/equipment/equipment_tab_bar.dart';

void main() {
  testWidgets('reveals hidden equipment tabs by touch and follows scrolling', (
    tester,
  ) async {
    const labels = [
      'Methods',
      'Presets',
      'Grinders',
      'Accessories',
      'Water',
      'Recipients',
      'Portafilters',
    ];
    final controller = TabController(length: labels.length, vsync: tester);
    addTearDown(controller.dispose);
    Future<void> show(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: EquipmentTabBar(controller: controller, labels: labels),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final arrow = find.byIcon(Icons.chevron_right);
    await show(320);
    expect(arrow, findsOneWidget);
    expect(find.text('Water').hitTestable(), findsNothing);
    final water = find.text('Water');
    for (
      var i = 0;
      i < labels.length && water.hitTestable().evaluate().isEmpty;
      i++
    ) {
      final before = tester.getCenter(water).dx;
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      expect(tester.getCenter(water).dx, lessThan(before));
    }
    expect(water.hitTestable(), findsOneWidget);
    expect(controller.index, 0);
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(controller.index, 4);
    await tester.drag(find.byType(TabBar), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(arrow, findsNothing);
    await tester.drag(find.byType(TabBar), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(arrow, findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(1600);
    expect(arrow, findsNothing);
  });
}
