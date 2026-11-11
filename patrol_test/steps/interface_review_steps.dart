import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

/// The interface review on the phone: Up next on Home, tuning the last brew
/// with − and + and saving it, the running timer as an ongoing notification,
/// swiping a bean to brew and the history filters as chips.
/// The isolated package is granted notifications on its own dialog first.
Future<void> checkInterfaceReview(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Review espresso',
    roaster: 'Test',
    initialGrams: 250,
  );
  final method = await repository.createMethod(
    name: 'Review lever',
    category: 'espresso',
  );
  await repository.createBrew(
    coffeeId: coffee,
    methodId: method,
    methodName: 'Review lever',
    grindSetting: '1.2',
    doseGrams: 18,
    beverageGrams: 36,
    temperatureC: 92,
    timeSeconds: 28,
    rating: 8,
    brewedAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );

  // Each coffee on Home has Repeat and Adjust.
  final adjust = find.byKey(ValueKey('home-adjust-$coffee'));
  await $.scrollUntilVisible(finder: adjust);
  await $.takeNativeScreenshot('interface-home-coffees');
  await $.tap(adjust);
  // The last brew's card and advice now come first, so the steps may need
  // a scroll.
  final adjustForm = find
      .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
      .first;
  expect(find.byKey(const ValueKey('brew-adjust-section')), findsOneWidget);
  for (final key in ['adjust-grind-less', 'adjust-dose-more']) {
    await $.scrollUntilVisible(
      finder: find.byKey(ValueKey(key)),
      view: adjustForm,
    );
    await $.tap(find.byKey(ValueKey(key)));
  }
  expect(
    $.tester
        .widget<TextFormField>(find.byKey(const ValueKey('adjust-grind-field')))
        .controller!
        .text,
    '1.1',
  );
  await $.takeNativeScreenshot('interface-adjust');

  // The running timer can be read from the notification shade, once the
  // isolated package may post notifications (granted on its dialog).
  final notifications = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  final asked = notifications?.requestNotificationsPermission();
  if (await $.platformAutomator.mobile.isPermissionDialogVisible(
    timeout: const Duration(seconds: 5),
  )) {
    await $.platformAutomator.mobile.grantPermissionWhenInUse();
  }
  await asked;

  // The timer is centred, clear of the scroll cue at the sheet's foot.
  final timer = find.byKey(const ValueKey('extraction-timer'));
  Future<void> showTimer() async {
    await Scrollable.ensureVisible($.tester.element(timer), alignment: 0.5);
    await $.pumpAndSettle();
  }

  await showTimer();
  await $.tap(timer);
  await Future<void>.delayed(const Duration(seconds: 3));
  // Patrol reads what the open shade shows.
  await $.platformAutomator.mobile.openNotifications();
  await $.takeNativeScreenshot('interface-timer-notification');
  final notices = await $.platformAutomator.mobile.getNotifications();
  await $.platformAutomator.mobile.closeNotifications();
  expect(
    notices.any(
      (Notification notice) =>
          notice.title.contains('Review espresso') ||
          notice.content.contains('Review espresso'),
    ),
    isTrue,
    reason: 'the brew in progress shows as an ongoing notification',
  );
  await $.pump(const Duration(seconds: 1));
  await showTimer();
  await $.tap(timer);
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.byKey(const ValueKey('brew-saved-rate-later')));
  final tuned = (await database.select(database.brews).get()).singleWhere(
    (brew) => brew.rating == null,
  );
  expect(tuned.grindSetting, '1.1');
  expect(tuned.doseGrams, 18.1);
  await $.platformAutomator.mobile.openNotifications();
  final after = await $.platformAutomator.mobile.getNotifications();
  await $.platformAutomator.mobile.closeNotifications();
  expect(
    after.any(
      (Notification notice) => notice.title.contains('Review espresso'),
    ),
    isFalse,
    reason: 'the notification goes when the timer stops',
  );

  // History: archived brews and filters are chips under the search.
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.waitUntilVisible(find.byKey(const ValueKey('history-filter-button')));
  await $.tap(find.byKey(const ValueKey('history-show-archived')));
  expect(
    $.tester
        .widget<FilterChip>(find.byKey(const ValueKey('history-show-archived')))
        .selected,
    isTrue,
  );
  await $.tap(find.byKey(const ValueKey('history-show-archived')));
  await $.takeNativeScreenshot('interface-history-chips');

  // Beans: a swipe to the right brews with the bean.
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  final card = find.byKey(ValueKey('bean-card-$coffee'));
  await $.waitUntilVisible(card);
  await $.tester.drag(card, const Offset(320, 0));
  await $.pumpAndSettle();
  expect(find.byType(BrewForm), findsOneWidget);
  await $.tap(find.text('Cancel').last);
  await $.pumpAndSettle();
}
