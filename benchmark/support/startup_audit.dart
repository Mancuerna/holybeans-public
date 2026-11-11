import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/main.dart' as app;

import 'audit_metrics.dart';
import 'journal_fixture.dart';
import 'journal_ui_audit.dart';

// Only invoke inside the isolated Patrol app after its data has been cleared.
// This exercises real startup services with no paired devices or Drive account.
Future<void> runStartupAudit(WidgetTester tester, AuditRecord record) async {
  final file = await AppDatabase.file();
  expect(
    file.existsSync(),
    isFalse,
    reason: 'startup audit requires an empty isolated Patrol package',
  );
  for (final count in [0, 5000]) {
    if (count != 0) {
      final seed = await AppDatabase.open();
      try {
        await JournalFixture(count, 2048).seed(seed);
      } finally {
        await seed.close();
      }
    }
    final samples = <double>[];
    for (var round = 0; round < 5; round++) {
      final watch = Stopwatch()..start();
      await app.main();
      await settleJournal(tester);
      watch.stop();
      samples.add(watch.elapsedMicroseconds / 1000);
      final running = tester.widget<app.HolyBeansApp>(
        find.byType(app.HolyBeansApp),
      );
      // Never initiate device discovery, reminders, or remote backups here.
      expect(running.services.driveSync?.enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await running.services.database.close();
    }
    record({
      'operation': 'real_main_to_loaded_shell',
      'brews': count,
      'scope':
          'same process, services and SQLite reopen; excludes OS/engine launch',
      'firstMs': samples.first,
      'subsequent': distribution(samples.skip(1).toList()),
    });
  }
}
