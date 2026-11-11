import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  Future<void> openSettings(
    WidgetTester tester, {
    required Future<void> Function() export,
    Future<void> Function()? restore,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      localizedApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        home: SettingsPage(
          locale: const Locale('en'),
          onLocaleChanged: (_) {},
          onExportBackup: export,
          onExportCsv: () {},
          onImportBackup: restore ?? () async {},
          parameterSettings: BrewParameterSettings(db),
          templateSettings: ShareTemplateSettings(db),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tile(String label) => find.ancestor(
    of: find.text(label, skipOffstage: false),
    matching: find.byType(ListTile, skipOffstage: false),
  );
  final progress = find.byKey(const ValueKey('backup-progress'));

  for (final action in ['Share backup', 'Restore backup']) {
    testWidgets('$action stays busy until completion and rejects repeats', (
      tester,
    ) async {
      final pending = Completer<void>();
      var calls = 0;
      Future<void> work() {
        calls++;
        return pending.future;
      }

      await openSettings(tester, export: work, restore: work);
      final queuedTap = tester.widget<ListTile>(tile(action)).onTap!;
      await tester.tap(find.text(action));
      // The modal blocks new taps; a callback already queued is guarded too.
      await tester.tap(find.text(action), warnIfMissed: false);
      queuedTap();
      await tester.pump();
      expect(calls, 1);
      expect(progress, findsOneWidget);
      expect(find.text('Processing backup…'), findsOneWidget);
      for (final label in ['Share backup', 'Restore backup']) {
        expect(tester.widget<ListTile>(tile(label)).enabled, isFalse);
      }
      await tester.tapAt(const Offset(5, 5));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(progress, findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
      for (final label in ['Share backup', 'Restore backup']) {
        expect(tester.widget<ListTile>(tile(label)).enabled, isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failure reports the error and allows another backup', (
    tester,
  ) async {
    var calls = 0;
    await openSettings(
      tester,
      export: () async {
        calls++;
        if (calls == 1) throw StateError('Synthetic backup failure');
      },
    );
    await tester.tap(find.text('Share backup'));
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(find.text('Could not prepare backup'), findsOneWidget);
    await tester.tap(find.text('Share backup'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(progress, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing removes only its progress route', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final pending = Completer<void>();
    await openSettings(
      tester,
      navigatorKey: navigator,
      export: () => pending.future,
    );
    await tester.tap(find.text('Share backup'));
    await tester.pump();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Confirmation')),
      ),
    );
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Confirmation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('backup-progress'), skipOffstage: false),
      findsNothing,
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion after disposal does not touch the old navigator', (
    tester,
  ) async {
    final pending = Completer<void>();
    await openSettings(tester, export: () => pending.future);
    await tester.tap(find.text('Share backup'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
