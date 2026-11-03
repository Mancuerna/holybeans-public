import 'dart:math' as math;

import 'package:holybeans/data/database/app_database.dart';

/// Days after which a backup is due again.
const backupReminderDays = 30;

/// Whether a backup is due on [now]: never saved, or saved more than
/// [backupReminderDays] ago, once the journal has been in use
/// that long ([firstUse], the oldest brew or coffee; null for an empty one).
bool backupDue({
  required DateTime? lastBackup,
  required DateTime? firstUse,
  required DateTime now,
}) {
  final since = lastBackup ?? firstUse;
  if (since == null) return false;
  return now.difference(since).inDays >= backupReminderDays;
}

/// When the journal started to be used: its oldest coffee or brew, or null
/// while it is empty.
DateTime? journalFirstUse(List<Coffee> coffees, List<Brew> brews) {
  final times = [
    for (final coffee in coffees) coffee.createdAtMs,
    for (final brew in brews) brew.createdAtMs,
  ];
  if (times.isEmpty) return null;
  return DateTime.fromMillisecondsSinceEpoch(times.reduce(math.min));
}
