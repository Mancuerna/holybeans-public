import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets('create and select a vessel at 320 px, $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      Recipient? selected;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Padding(
                padding: const EdgeInsets.all(12),
                child: RecipientPicker(
                  repository: repo,
                  value: selected?.id,
                  snapshot: selected,
                  onChanged: (row) => setState(() => selected = row),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(locale == 'es' ? 'Añadir recipiente' : 'Add vessel'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recipient-name')),
        'Hario glass',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipient-grams')),
        '185,5',
      );
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              locale == 'es' ? 'Guardar' : 'Save',
            ),
          )
          .onPressed!;
      // Both events can arrive before the disabled button is rebuilt.
      save();
      save();
      await tester.pumpAndSettle();
      expect(selected?.name, 'Hario glass');
      expect(selected?.emptyGrams, 185.5);
      expect((await db.select(db.recipients).getSingle()).id, selected?.id);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              locale == 'es'
                  ? 'Peso neto, sin recipiente'
                  : 'Net weight, no vessel',
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }
}
