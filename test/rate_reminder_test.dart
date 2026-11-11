import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

class _FakeReminders implements RateReminders {
  bool permission = true;
  final scheduled = <(String, Duration, String)>[];
  final cancelled = <String>[];

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> schedule({
    required String brewId,
    required Duration after,
    required String title,
    required String body,
  }) async => scheduled.add((brewId, after, body));

  @override
  Future<void> cancel(String brewId) async => cancelled.add(brewId);
}

void main() {
  test('reminder ids are stable and positive', () {
    final id = reminderIdFor('5f0c2d1e-0000-4000-8000-000000000001');
    expect(id, reminderIdFor('5f0c2d1e-0000-4000-8000-000000000001'));
    expect(id, isNonNegative);
    expect(id, isNot(reminderIdFor('5f0c2d1e-0000-4000-8000-000000000002')));
  });

  testWidgets('unrated brews schedule a reminder that opens the rate sheet', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Remind me', roaster: 'Roaster');
    await repository.createMethod(name: 'V60', category: 'pourover');
    final reminders = _FakeReminders();
    final openRate = ValueNotifier<String?>(null);
    addTearDown(openRate.dispose);

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(
          database: database,
          reminders: reminders,
          openRate: openRate,
        ),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    // Permission refused: the setting stays off.
    reminders.permission = false;
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('rate-reminder-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Notification permission denied'), findsOneWidget);
    expect(await RateReminderSettings(database).loadMinutes(), isNull);

    reminders.permission = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(await RateReminderSettings(database).loadMinutes(), 20);
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();
    expect(await RateReminderSettings(database).loadMinutes(), 5);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brew').last);
    await tester.pumpAndSettle();
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Choose a method',
    );
    await tester.scrollUntilVisible(
      selector,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('V60').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final brew = await database.select(database.brews).getSingle();
    expect(reminders.scheduled, [
      (
        brew.id,
        const Duration(minutes: 5),
        'Remind me: note down how the cup turned out',
      ),
    ]);

    // Tapping the notification opens the rate sheet for that brew.
    openRate.value = brew.id;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rate-brew-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rate-brew-save')));
    await tester.pumpAndSettle();
    expect(reminders.cancelled, [brew.id]);
    expect(openRate.value, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
