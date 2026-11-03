import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/freshness_calendar_page.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    patrolTest(
      'roasters and freshness calendar reopen and navigate in $language',
      tags: ['android', 'beans-views'],
      ($) async {
        var db = await openTestDatabase();
        try {
          $.tester.platformDispatcher.platformBrightnessTestValue =
              language == 'es' ? Brightness.dark : Brightness.light;
          await clearTestData(db);
          final repo = JournalRepository(db);
          final now = DateTime.now();
          await ListOptionsSettings(db)
              .save(const ListOptions(beansCompact: true));
          for (final (name, roaster, age) in [
            ('Kenya', 'Big Sur', 12),
            ('Colombia', 'Big Sur', 1),
            ('Ethiopia', 'North', 60),
          ]) {
            await repo.createCoffee(
              name: name,
              roaster: roaster,
              initialGrams: 250,
              roastDate: formatIsoCalendarDate(
                DateTime(now.year, now.month, now.day - age),
              ),
            );
          }
          Future<void> openBeans() async {
            await $.pumpWidgetAndSettle(
              HolyBeansApp(database: db, initialLocale: Locale(language)),
            );
            final nav = $.tester.getRect(find.byType(NavigationBar));
            await $.tester.tapAt(
              Offset(nav.left + nav.width * 1.5 / 4, nav.center.dy),
            );
            await $.pumpAndSettle();
          }

          await openBeans();
          await $.tap(find.byKey(const ValueKey('beans-view-menu')));
          await $.tap(find.byKey(const ValueKey('beans-view-roasters')));
          await $.tap(find.byKey(const ValueKey('roaster-group-big sur')));
          await $.takeNativeScreenshot('roasters-expanded-$language');
          expect(find.byType(BeanCard), findsNWidgets(2));
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          await db.close();
          db = await openTestDatabase();
          expect((await ListOptionsSettings(db).load()).beansByRoaster, isTrue);
          await openBeans();
          await $.tap(find.byKey(const ValueKey('beans-view-menu')));
          expect(
            $.tester
                .widget<CheckedPopupMenuItem<int>>(
                  find.byKey(const ValueKey('beans-view-roasters')),
                )
                .checked,
            isTrue,
          );
          await $.tap(find.byKey(const ValueKey('beans-view-roasters')));
          await $.enterText(find.byType(TextField).first, 'Kenya');
          expect(find.text('Kenya'), findsWidgets);
          expect(
            $.tester.widget<BeanCard>(find.byType(BeanCard)).coffee.name,
            'Kenya',
          );
          await $.enterText(find.byType(TextField).first, '');
          await $.tap(find.byKey(const ValueKey('beans-calendar')));
          await $.waitUntilVisible(find.byType(FreshnessCalendarPage));
          await $.tap(find.byKey(const ValueKey('calendar-next')));
          await $.tap(find.byKey(const ValueKey('calendar-style-espresso')));
          await $.tap(find.byKey(const ValueKey('calendar-today')));
          final nextDay = DateTime(now.year, now.month, now.day + 1);
          if (nextDay.month != now.month) {
            await $.tap(find.byKey(const ValueKey('calendar-next')));
          }
          await $.tap(
            find.byKey(
              ValueKey('calendar-day-${formatIsoCalendarDate(nextDay)}'),
            ),
          );
          await $.takeNativeScreenshot('freshness-calendar-$language');
          await $.platform.android.pressBack();
          await $.waitUntilVisible(
            find.byKey(const ValueKey('beans-view-menu')),
          );
          await $.tap(find.byKey(const ValueKey('beans-calendar')));
          await $.waitUntilVisible(find.byType(FreshnessCalendarPage));
          await $.tap(find.byType(BackButton));
          await $.pumpAndSettle();
          expect((await ListOptionsSettings(db).load()).beansByRoaster, isTrue);
          expect(await JournalRepository(db).allCoffees(), hasLength(3));
        } finally {
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          $.tester.platformDispatcher.clearPlatformBrightnessTestValue();
          await db.close();
        }
      },
    );
  }
}
