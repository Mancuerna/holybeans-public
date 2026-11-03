import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

/// Folder with a BeanConqueror "Full export to directory" (its
/// Beanconqueror.zip and `brews` folder), copied beforehand with
/// `adb shell cp -r <export> /sdcard/Documents/HolyBeansPatrolBQ`.
const patrolBqFolder = 'HolyBeansPatrolBQ';

/// Imports a BeanConqueror export by picking its folder with Android's
/// picker: every curve it refers to is found and read one by one, however
/// many there are, without the app running out of memory.
Future<void> checkBeanconquerorFolder(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      database: database,
      initialLocale: const Locale('en'),
      exportFolder: const AndroidExportFolder(),
    ),
  );
  await $.tap(find.byTooltip('Settings'));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('import-beanconqueror')),
  );
  await $.tap(find.byKey(const ValueKey('import-beanconqueror')));
  await $.tap(find.byKey(const ValueKey('bq-source-folder')));
  final mobile = $.platform.mobile;
  await mobile.tap(Selector(text: 'Documents'));
  await mobile.tap(Selector(text: patrolBqFolder));
  await mobile.tap(Selector(text: 'USE THIS FOLDER'));
  await mobile.tap(Selector(text: 'ALLOW'));

  // When each step first shows, in ms from the step's start; for the
  // run's output.
  final shown = <String, int>{};
  final count = find.byKey(const ValueKey('bq-curve-count'));
  final reading = Stopwatch()..start();
  await _watch($, shown, reading, ['Reading the export…'], until: count);
  shown['plan'] = reading.elapsedMilliseconds;
  await $.takeNativeScreenshot('bq-folder-plan');
  // Every curve the export refers to is in the folder.
  final text = $.tester.widget<Text>(count).data!;
  final match = RegExp(r'Curves: (\d+) of (\d+)').firstMatch(text)!;
  expect(match.group(1), match.group(2));
  final wanted = int.parse(match.group(2)!);

  final clock = Stopwatch()..start();
  await $.scrollUntilVisible(finder: find.byKey(const ValueKey('bq-import')));
  // Without settling: the progress bar keeps moving, and waiting for it
  // would hide the first ten seconds from the timings.
  await $.tap(
    find.byKey(const ValueKey('bq-import')),
    settlePolicy: SettlePolicy.noSettle,
  );
  await _watch($, shown, clock, [
    'Reading curves',
    'Saving to your journal…',
  ], until: find.byKey(const ValueKey('import-beanconqueror')));
  // The timing goes to the run's output, for comparing import speed.
  // ignore: avoid_print
  print(
    'BeanConqueror folder: $wanted curves in ${clock.elapsed.inSeconds} s; '
    'steps first shown at (ms) $shown',
  );
  expect(await database.select(database.brewCurves).get(), hasLength(wanted));
}

/// Pumps until [until] shows, noting in [shown] when each of [labels]
/// first appears, by [clock]; fails after five minutes.
Future<void> _watch(
  PatrolIntegrationTester $,
  Map<String, int> shown,
  Stopwatch clock,
  List<String> labels, {
  required Finder until,
}) async {
  final end = clock.elapsed + const Duration(minutes: 5);
  while (until.evaluate().isEmpty) {
    expect(clock.elapsed, lessThan(end), reason: 'still waiting for $until');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await $.tester.pump();
    for (final label in labels) {
      if (find.textContaining(label).evaluate().isNotEmpty) {
        shown.putIfAbsent(label, () => clock.elapsedMilliseconds);
      }
    }
  }
}
