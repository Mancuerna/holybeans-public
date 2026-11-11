import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_share_sheet.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/beans/freshness_calendar_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../test/helpers/fake_niimbot_ble_platform.dart';
import 'support/smoke_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    patrolTest(
      'coffee menu opens labels and keeps sharing available ($language)',
      tags: ['android', 'label-menu'],
      ($) async {
        expect(
          await const DriveNativeClient().channel.invokeMethod<String>(
            'package',
          ),
          'com.caffeinateddev.holybeans.patrol',
        );
        final db = await openTestDatabase();
        await clearTestData(db);
        final platform = FakeNiimbotBlePlatform();
        UniversalBle.setInstance(platform);
        final repo = JournalRepository(db);
        final id = await repo.createCoffee(
          name: 'Menu Sidama',
          roaster: 'HolyBeans',
          initialGrams: 250,
          roastDate: '2026-10-20',
        );
        final s = await AppLocalizations.delegate.load(Locale(language));
        try {
          await $.pumpWidgetAndSettle(
            HolyBeansApp(
              services: AppServices(database: db),
              initialLocale: Locale(language),
            ),
          );
          final bar = $.tester.getRect(find.byType(NavigationBar));
          await $.tester.tapAt(
            Offset(bar.left + bar.width * 1.5 / 4, bar.center.dy),
          );
          await $.pumpAndSettle();
          await $(const ValueKey('beans-calendar')).tap();
          await $.waitUntilVisible(find.byType(FreshnessCalendarPage));
          expect(find.text(s.freshnessCalendar), findsOneWidget);
          await $(find.byType(BackButton)).tap();
          await $(const ValueKey('beans-view-menu')).tap();
          await $(const ValueKey('beans-view-roasters')).tap();
          await $(const ValueKey('roaster-group-holybeans')).tap();
          final menu = find.byKey(ValueKey('bean-menu-$id'));
          await $(menu).tap();
          await $.takeNativeScreenshot('label-menu-$language');
          await $(const ValueKey('bean-print-label')).tap();
          await $.waitUntilVisible(find.byType(LabelPrintPage));
          expect(find.text('Menu Sidama'), findsOneWidget);
          expect(find.text(s.labelTitle), findsOneWidget);
          expect(platform.commands, isEmpty);
          await $.takeNativeScreenshot('label-menu-open-$language');
          await $(find.byType(BackButton)).tap();
          await $.pumpAndSettle();
          expect(find.byType(LabelPrintPage), findsNothing);
          await $(find.text('Menu Sidama')).tap();
          await $.pumpAndSettle();
          expect(find.byType(CoffeeDetailsSheet), findsOneWidget);
          expect(find.text(s.labelPrint), findsNothing);
          await $.takeNativeScreenshot('label-details-clean-$language');
          await $.platformAutomator.android.pressBack();
          await $.pumpAndSettle();
          await $(menu).tap();
          await $(const ValueKey('bean-share-card')).tap();
          await $.waitUntilVisible(find.byType(BeanShareSheet));
          expect(platform.commands, isEmpty);
          expect((await repo.coffeeLots(id)).single.remainingGrams, 250);
        } finally {
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          await db.close();
        }
      },
    );
  }
}
