import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('live updates are harmless on Android 7 and work on Android 8+', (
    $,
  ) async {
    await $.pumpWidgetAndSettle(
      const MaterialApp(home: Scaffold(body: Text('Live update probe'))),
    );
    final sdk = await $.platform.mobile.getOsVersion();
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_holybeans'),
      ),
    );
    if (sdk >= 33) {
      final permission = notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!
          .requestNotificationsPermission();
      if (await $.platform.mobile.isPermissionDialogVisible()) {
        await $.platform.mobile.grantPermissionWhenInUse();
      }
      expect(await permission, isTrue);
    }
    // Call the real channel directly: the app wrapper tolerates platform errors,
    // but a compatibility regression must fail this test rather than disappear.
    const channel = MethodChannel('holybeans/live-update');
    try {
      await channel.invokeMethod<void>('clear');
      for (final pours in [false, true]) {
        final title = pours ? 'Audit pours' : 'Audit timer';
        await channel.invokeMethod<void>('show', {
          'title': title,
          'text': 'Running',
          'startedAtMs': DateTime.now().millisecondsSinceEpoch,
          if (pours) 'segments': [100, 200],
          if (pours) 'progress': 150,
        });
        await expectNotice(notifications, sdk < 26 ? null : title);
      }
      await const MethodChannel('holybeans/device').invokeMethod<void>(
        'setSurfaceLabels',
        {'liveUpdateChannel': 'Audit channel'},
      );
      if (sdk >= 26) {
        final channels = await notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!
            .getNotificationChannels();
        expect(
          channels!.singleWhere((value) => value.id == 'brew_in_progress').name,
          'Audit channel',
        );
      }
      expect(find.text('Live update probe'), findsOneWidget);
    } finally {
      await channel.invokeMethod<void>('clear');
    }
    await expectNotice(notifications, null);
  });
}

Future<void> expectNotice(
  FlutterLocalNotificationsPlugin notifications,
  String? title,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final own = (await notifications.getActiveNotifications())
        .where((notice) => notice.id == 7301)
        .toList();
    final matches = title == null
        ? own.isEmpty
        : own.length == 1 && own.single.title == title;
    if (matches || DateTime.now().isAfter(deadline)) {
      expect(matches, isTrue, reason: 'Expected live update title: $title');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
