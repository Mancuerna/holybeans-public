import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('new beans reuse roaster and producer from archived beans', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final archived = await repository.createCoffeeWithComponents(
      name: 'Old coffee',
      roaster: 'Friedhats',
      components: const [
        CoffeeComponentInput(
          producer: 'Edwin Noreña',
          variety: 'Pink Bourbon',
          process: 'Natural',
        ),
      ],
    );
    await repository.setCoffeeArchived(archived, archived: true);
    final suggestions = await repository.coffeeSuggestions();
    expect(suggestions.producers, ['Edwin Noreña']);
    expect(suggestions.roasters, ['Friedhats']);
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bean'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Coffee name'),
      'New coffee',
    );
    final roaster = find.widgetWithText(TextFormField, 'Roaster');
    await tester.enterText(roaster, 'fri');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friedhats').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(roaster).controller!.text, 'Friedhats');
    final scrollable = verticalScrollable(find.byType(CoffeeForm));
    final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
    await tester.scrollUntilVisible(addOrigin, 240, scrollable: scrollable);
    await tester.tap(addOrigin);
    await tester.pumpAndSettle();
    final producer = find.widgetWithText(TextFormField, 'Producer');
    await tester.scrollUntilVisible(producer, 160, scrollable: scrollable);
    await tester.enterText(producer, 'edwin nore');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edwin Noreña').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(producer).controller!.text,
      'Edwin Noreña',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final coffee = (await repository.allCoffees()).singleWhere(
      (coffee) => coffee.id != archived,
    );
    expect(coffee.roaster, 'Friedhats');
    expect(
      (await repository.coffeeComponents(coffee.id)).single.producer,
      'Edwin Noreña',
    );
    expect((await repository.coffee(archived))!.archivedAtMs, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
