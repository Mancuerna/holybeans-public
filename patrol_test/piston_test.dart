import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/piston/piston_page.dart';
import 'package:patrol/patrol.dart';

import '../test/helpers/piston_fake.dart';
import 'support/smoke_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    patrolTest(
      'piston history and maintenance remain available offline in $language',
      tags: ['android', 'piston'],
      ($) async {
        final db = await openTestDatabase();
        final original = connectPistonHistory;
        try {
          await clearTestData(db);
          final repo = JournalRepository(db);
          final method = await repo.createMethod(
            name: 'Meticulous',
            category: 'espresso',
            machine: 'meticulous',
            machineAddress: 'meticulous.local',
          );
          final source = FakePistonSource(pistonFixture());
          connectPistonHistory = (_) => source;
          $.tester.platformDispatcher.platformBrightnessTestValue =
              language == 'es' ? Brightness.dark : Brightness.light;
          await $.pumpWidgetAndSettle(
            HolyBeansApp(database: db, initialLocale: Locale(language)),
          );
          final s = lookupAppLocalizations(Locale(language));
          await $.tap(find.text(s.equipment).last);
          final entry = find.byKey(ValueKey('piston-method-$method'));
          await $.scrollUntilVisible(
            finder: entry,
            view: verticalScrollable(find.byType(Scaffold).last),
          );
          await $.tap(entry);
          await $.waitUntilVisible(find.byType(PistonPage));
          await $.tap(find.byKey(const ValueKey('piston-refresh')));
          await $.waitUntilVisible(find.byType(PistonChart));
          expect((await repo.piston.load(method)).readings, hasLength(280));
          await $.tap(find.text(s.pistonAll));
          await $.takeNativeScreenshot('piston-chart-$language');
          final view = verticalScrollable(find.byType(PistonPage));
          await $.scrollUntilVisible(
            finder: find.byKey(const ValueKey('piston-add-service')),
            view: view,
          );
          await $.tap(find.byKey(const ValueKey('piston-add-service')));
          await $.enterText(
            find.byKey(const ValueKey('piston-service-notes')),
            'Patrol maintenance',
          );
          await $.tap(find.byKey(const ValueKey('piston-service-save')));
          expect(
            (await repo.piston.load(method)).services.single.notes,
            'Patrol maintenance',
          );
          await $.takeNativeScreenshot('piston-maintenance-$language');
          await $.platform.android.pressBack();
          connectPistonHistory = (_) => FakePistonSource([], offline: true);
          await $.tap(entry);
          await $.waitUntilVisible(find.text(s.pistonOffline));
          await $.takeNativeScreenshot('piston-offline-$language');
          expect((await repo.piston.load(method)).readings, hasLength(280));
          expect(await repo.allBrews(), isEmpty);
          await $.platform.android.pressBack();
        } finally {
          connectPistonHistory = original;
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          $.tester.platformDispatcher.clearPlatformBrightnessTestValue();
          await db.close();
        }
      },
    );
  }
}
