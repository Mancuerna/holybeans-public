import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freezer_widgets.dart';
import 'package:holybeans/ui/cupping/cupping_sessions_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

Widget _app(Widget page) =>
    localizedApp(locale: const Locale('en'), home: page);

void main() {
  testWidgets('an invalid frozen date keeps the portion visible and editable', (
    tester,
  ) async {
    var edited = false;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: FrozenPortionCard(
            portion: const FrozenPortion(
              id: 'portion',
              lotId: 'lot',
              label: 'A1',
              frozenDate: 'not-a-date',
              initialGrams: 20,
              remainingGrams: 15,
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
            roastDate: DateTime(2026),
            onThaw: () {},
            onThawAndBrew: () {},
            onEdit: () => edited = true,
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('15 / 20 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('frozen-age-portion')), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(lookupAppLocalizations(const Locale('en')).editFrozenPortion),
    );
    await tester.pumpAndSettle();
    expect(edited, isTrue);
  });

  for (final damaged in ['{', '[]']) {
    testWidgets('a damaged cupping draft keeps the list usable ($damaged)', (
      tester,
    ) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repository = JournalRepository(db);
      await repository.createCuppingSession(CuppingDraft()..name = 'Healthy');
      final id = await repository.createCuppingSession(
        CuppingDraft()..name = 'Damaged',
      );
      await db.customStatement(
        'UPDATE cupping_sessions SET draft_json = ? WHERE id = ?',
        [damaged, id],
      );
      await tester.pumpWidget(
        _app(CuppingSessionsPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Healthy'), findsOneWidget);
      final row = find.widgetWithText(ListTile, 'Damaged');
      expect(tester.widget<ListTile>(row).onTap, isNull);
      final s = lookupAppLocalizations(const Locale('en'));
      expect(find.textContaining(s.dataError), findsOneWidget);
      expect((await repository.cuppingSession(id))!.draftJson, damaged);
      await tester.tap(
        find.descendant(of: row, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, s.cuppingDiscard));
      await tester.pumpAndSettle();
      expect(await repository.cuppingSession(id), isNull);
      expect(find.text('Healthy'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }
}
