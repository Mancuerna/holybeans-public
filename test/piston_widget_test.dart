import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/piston/piston_page.dart';

import 'helpers/piston_fake.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'cached chart, range, maintenance and offline reopening in $language',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'GB');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final db = memoryDatabase();
        final repo = JournalRepository(db);
        final method = await repo.createMethod(name: 'Meticulous');
        final original = connectPistonHistory;
        final source = FakePistonSource(pistonFixture());
        connectPistonHistory = (_) => source;
        addTearDown(() async {
          connectPistonHistory = original;
          await db.close();
        });
        final s = lookupAppLocalizations(Locale(language));
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: PistonPage(
              repository: repo.piston,
              methodId: method,
              address: 'test',
              name: 'Meticulous',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.pistonStart), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('piston-refresh')));
        await tester.pumpAndSettle();
        expect(find.byType(PistonChart), findsOneWidget);
        expect(find.textContaining('07/10/2026'), findsWidgets);
        expect(find.textContaining('1.348 A'), findsOneWidget);
        await tester.tap(find.text(s.pistonAll));
        await tester.pumpAndSettle();
        expect(
          tester.widget<PistonChart>(find.byType(PistonChart)).points,
          hasLength(280),
        );
        await tester.tap(find.text(s.pistonSpeed));
        await tester.pumpAndSettle();
        expect(
          tester.widget<PistonChart>(find.byType(PistonChart)).speed,
          true,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('piston-add-service')),
          300,
        );
        await tester.tap(find.byKey(const ValueKey('piston-add-service')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('piston-service-notes')),
          'Test maintenance',
        );
        await tester.tap(find.byKey(const ValueKey('piston-service-save')));
        await tester.pumpAndSettle();
        expect(
          (await repo.piston.load(method)).services.single.notes,
          'Test maintenance',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        connectPistonHistory = (_) => FakePistonSource([], offline: true);
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: PistonPage(
              repository: repo.piston,
              methodId: method,
              address: 'test',
              name: 'Meticulous',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.pistonOffline), findsOneWidget);
        expect((await repo.piston.load(method)).readings, hasLength(280));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
