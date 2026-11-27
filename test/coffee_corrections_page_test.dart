import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/settings/coffee_corrections_page.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'reviews individual origins, uses bundled country suggestion and exports backup',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final journal = JournalRepository(db);
      final id = await journal.createCoffeeWithComponents(
        name: 'Blend',
        roaster: 'R',
        components: const [
          CoffeeComponentInput(country: 'Perù'),
          CoffeeComponentInput(country: 'Perù'),
        ],
      );
      var exported = 0;
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('es'),
          home: CoffeeCorrectionsPage(
            database: db,
            exportBackup: () async {
              exported++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.backup_outlined));
      await tester.pumpAndSettle();
      expect(exported, 1);
      await tester.enterText(find.byType(TextField), 'PERU');
      await tester.pumpAndSettle();
      expect(find.text('Cafés: 1'), findsOneWidget);
      await tester.tap(find.text('Perù'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar cambios'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Per');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perú'));
      await tester.pumpAndSettle();
      expect(find.text('Orígenes: 2 · Cafés: 1'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      expect(find.text('Orígenes: 1 · Cafés: 1'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Cambios guardados'), findsOneWidget);
      expect((await journal.coffeeComponents(id)).map((r) => r.country), [
        'Perú',
        'Perù',
      ]);
    },
  );

  testWidgets(
    'opens from advanced settings and assigns two spellings to a directory profile',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      await repo.createCoffee(name: 'A', roaster: 'Nomda');
      await repo.createCoffee(name: 'B', roaster: 'Nomadd');
      await RoasterRegistry(db).resolve('Nomad Coffee');
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: SettingsPage(
            services: AppServices(database: db),
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
            onExportBackup: () async {},
            onExportCsv: () {},
            onImportBackup: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct coffee data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roaster').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nomda'));
      await tester.pump();
      await tester.tap(find.text('Nomadd'));
      await tester.pump();
      await tester.tap(find.text('Review changes'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Nomad C');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nomad Coffee'));
      await tester.pumpAndSettle();
      expect(find.text('Coffees: 2'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Nomda'), findsNothing);
      expect(find.text('Nomadd'), findsNothing);
      expect(find.text('Nomad Coffee'), findsOneWidget);
      expect(find.text('Coffees: 2'), findsOneWidget);
    },
  );
}
