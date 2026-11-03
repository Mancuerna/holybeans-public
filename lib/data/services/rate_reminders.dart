import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the "how was your brew?" reminders. Kept behind an interface so
/// widget tests can use a fake instead of the platform plugin.
abstract class RateReminders {
  /// Asks for permission to post notifications; true when granted.
  Future<bool> requestPermission();

  Future<void> schedule({
    required String brewId,
    required Duration after,
    required String title,
    required String body,
  });

  Future<void> cancel(String brewId);
}

/// Stable positive notification id for a brew (FNV-1a of its ID), since
/// String.hashCode is not guaranteed to be stable across runs.
int reminderIdFor(String brewId) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(brewId)) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// [RateReminders] backed by flutter_local_notifications.
class LocalRateReminders implements RateReminders {
  LocalRateReminders._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationDetails(
    'rate_reminders',
    'Rate reminders',
    channelDescription: 'Reminders to rate a brew after drinking it',
    icon: 'ic_stat_holybeans',
    color: Color(0xFF9E1F35),
  );

  /// Initialises the plugin; [onOpen] receives the brew ID of a tapped
  /// reminder. Returns the brew ID that launched the app, if any.
  static Future<(LocalRateReminders, String?)> start({
    required void Function(String brewId) onOpen,
  }) async {
    tz_data.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_holybeans'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final brewId = response.payload;
        if (brewId != null) onOpen(brewId);
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    final launchBrew = launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
    return (LocalRateReminders._(plugin), launchBrew);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<void> schedule({
    required String brewId,
    required Duration after,
    required String title,
    required String body,
  }) => _plugin.zonedSchedule(
    id: reminderIdFor(brewId),
    scheduledDate: tz.TZDateTime.now(tz.UTC).add(after),
    notificationDetails: const NotificationDetails(android: _channel),
    // Inexact timing is fine for a reminder and needs no alarm permission.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: title,
    body: body,
    payload: brewId,
  );

  @override
  Future<void> cancel(String brewId) =>
      _plugin.cancel(id: reminderIdFor(brewId));
}
