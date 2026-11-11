import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

/// Nodes a screen reader would announce without a name: text fields,
/// switches, checkboxes and tappable controls whose label, value and tooltip
/// are all empty.
List<String> _unnamedControls(WidgetTester tester) {
  final problems = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final named =
        data.label.trim().isNotEmpty ||
        data.value.trim().isNotEmpty ||
        data.tooltip.trim().isNotEmpty ||
        data.hint.trim().isNotEmpty;
    final control =
        data.flagsCollection.isTextField ||
        data.flagsCollection.isToggled != Tristate.none ||
        data.flagsCollection.isChecked != CheckedState.none ||
        data.hasAction(SemanticsAction.tap);
    if (control && !named && !node.isInvisible) {
      problems.add('${node.id} ${data.flagsCollection} ${node.rect}');
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return problems;
}

void main() {
  testWidgets('main screens and the brew form name every control', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffeeWithComponents(
      name: 'Label coffee',
      roaster: 'Test roaster',
      components: const [],
      initialGrams: 250,
      flavorProfile: 'Cocoa',
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
      rating: 7,
    );

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final bounds = tester.getRect(find.byType(NavigationBar));
    Future<void> openTab(int index) async {
      await tester.tapAt(
        Offset(
          bounds.left + bounds.width * (index + 0.5) / 4,
          bounds.center.dy,
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(_unnamedControls(tester), isEmpty, reason: 'Home');
    for (final (index, name) in [
      (1, 'Beans'),
      (2, 'Brews'),
      (3, 'Equipment'),
    ]) {
      await openTab(index);
      expect(_unnamedControls(tester), isEmpty, reason: name);
    }

    await openTab(2);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var page = 0; page < 6; page++) {
      expect(_unnamedControls(tester), isEmpty, reason: 'Brew form $page');
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
