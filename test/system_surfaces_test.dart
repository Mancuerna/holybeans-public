import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';

void main() {
  testWidgets(
    'starting the app clears a stale brew notice and fills the widget',
    (tester) async {
      final notices = <String>[];
      final device = <MethodCall>[];
      const live = MethodChannel('holybeans/live-update');
      const deviceChannel = MethodChannel('holybeans/device');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(live, (call) async {
        notices.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(deviceChannel, (call) async {
        device.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(live, null);
        messenger.setMockMethodCallHandler(deviceChannel, null);
      });
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Widget bean',
        roaster: 'R',
        initialGrams: 250,
      );
      await repository.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        doseGrams: 15,
        waterGrams: 250,
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // A brew left running when the app last died loses its notice.
      expect(notices, ['clear']);
      final widgetUpdates = device.where(
        (call) => call.method == 'updateWidget',
      );
      expect(widgetUpdates, hasLength(1));
      expect((widgetUpdates.single.arguments as Map)['title'], 'Widget bean');
      expect(
        (widgetUpdates.single.arguments as Map)['recipe'],
        contains('15 g → 250 g'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('shortcuts, widget and notice are labelled in the app language', (
    tester,
  ) async {
    final device = <MethodCall>[];
    const deviceChannel = MethodChannel('holybeans/device');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      device.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(deviceChannel, null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    List<Map<Object?, Object?>> labels() => [
      for (final call in device)
        if (call.method == 'setSurfaceLabels')
          call.arguments as Map<Object?, Object?>,
    ];

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(labels(), hasLength(1));
    expect(labels().single['shortcutBrewLong'], 'New brew');
    expect(labels().single['liveUpdateChannel'], 'Brew in progress');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-es')),
      300,
    );
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    // Once more, in Spanish, and no more for the same language.
    expect(labels(), hasLength(2));
    expect(labels().last['shortcutBrewLong'], 'Nueva preparación');
    expect(labels().last['widgetEmpty'], 'Abre HolyBeans para rellenarlo');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
