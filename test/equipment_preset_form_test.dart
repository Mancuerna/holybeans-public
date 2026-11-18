import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/equipment/equipment_presets_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'create a named preset from real equipment and remove it before use',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repository = JournalRepository(db);
      final method = await repository.createMethod(name: 'V60');
      await repository.createMethodTool(methodId: method, name: 'Paper');
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: EquipmentPresetList(repository: repository),
            floatingActionButton: Builder(
              builder: (context) => FloatingActionButton(
                onPressed: () => showEquipmentPresetForm(context, repository),
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Filter set');
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Method'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('V60').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Paper'));
      await tester.tap(find.text('Paper'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Filter set'), findsOneWidget);
      expect(find.textContaining('V60 · Paper'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-equipment-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Filter set'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
