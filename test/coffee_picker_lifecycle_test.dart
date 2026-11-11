import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('selection survives a rebuilt field while search is open', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final first = await repo.createCoffee(name: 'First', roaster: 'R');
    final second = await repo.createCoffee(name: 'Second', roaster: 'R');
    final coffees = await repo.allCoffees();
    String? selected = first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CoffeePicker(
                repository: repo,
                coffees: coffees,
                value: selected,
                onChanged: (id) => setState(() => selected = id),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brew-coffee-picker')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(
      find.byKey(const ValueKey('brew-coffee-search')),
      'Second',
    );
    rebuild(() => selected = null);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('coffee-choice-$second')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selected, second);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
