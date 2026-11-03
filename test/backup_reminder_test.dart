import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/backup_reminder.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/main.dart';

void main() {
  test('a backup is due a month after the last one or the first use', () {
    final now = DateTime(2026, 10);
    final recent = now.subtract(const Duration(days: 10));
    final old = now.subtract(const Duration(days: 31));
    expect(backupDue(lastBackup: null, firstUse: null, now: now), isFalse);
    expect(backupDue(lastBackup: null, firstUse: recent, now: now), isFalse);
    expect(backupDue(lastBackup: null, firstUse: old, now: now), isTrue);
    expect(backupDue(lastBackup: recent, firstUse: old, now: now), isFalse);
    expect(backupDue(lastBackup: old, firstUse: old, now: now), isTrue);
  });

  test('the journal starts with its oldest coffee or brew', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    expect(journalFirstUse(const [], const []), isNull);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    await repository.createBrew(coffeeId: coffeeId, methodName: 'V60');
    final old = DateTime(2025, 1, 2);
    await database.customStatement('UPDATE brews SET created_at_ms = ?', [
      old.millisecondsSinceEpoch,
    ]);
    expect(
      journalFirstUse(
        await database.select(database.coffees).get(),
        await database.select(database.brews).get(),
      ),
      old,
    );
  });

  test('the mean rating ignores missing ratings', () {
    expect(meanRating(const []), isNull);
    expect(meanRating(const [null, null]), isNull);
    expect(meanRating(const [7, null, 8.5]), 7.75);
  });

  testWidgets('Home suggests a backup on an old journal until put off', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Old coffee', roaster: 'R');
    final longAgo = DateTime.now()
        .subtract(const Duration(days: 40))
        .millisecondsSinceEpoch;
    await database.customStatement('UPDATE coffees SET created_at_ms = ?', [
      longAgo,
    ]);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('You have not saved a backup of your journal yet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-reminder')), findsNothing);

    // After a backup, a fresh start does not remind again.
    await BackupSettings(database).markBackedUp(DateTime.now());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-reminder')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
