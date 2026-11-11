import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/app/startup_services.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';
import 'helpers/test_startup.dart';

void main() {
  for (final failure in [
    null,
    'reminders',
    'backups',
    'scale',
    'pressure',
    'refractometer',
    'drive',
    'language',
    'safety copy',
    'release notes',
  ]) {
    testWidgets('journal opens when $failure fails during startup', (
      tester,
    ) async {
      final database = memoryDatabase();
      final directory = Directory.systemTemp.createTempSync('startup-');
      final services = TestStartup(database, PhotoStore(directory), failure);
      addTearDown(() async {
        services.workingScale.dispose();
        await database.close();
        directory.deleteSync(recursive: true);
      });
      final app = await tester.runAsync(() => prepareApp(services: services));
      expect(app, isA<HolyBeansApp>());
      expect(
        (app as HolyBeansApp).services.scale,
        failure == 'scale' ? isNull : same(services.workingScale),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('No beans.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        services.started,
        containsAll([
          'reminders',
          'backups',
          'scale',
          'pressure',
          'refractometer',
          'drive',
          'language',
          'safety copy',
          'release notes',
        ]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  test('database opening checks SQLite before optional startup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'startup-database-',
    );
    final file = File(path.join(directory.path, 'holybeans.sqlite'));
    await file.writeAsString('unreadable journal');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      return directory.path;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    await expectLater(
      const StartupServices().openDatabase(),
      throwsA(isA<Exception>()),
    );
    expect(await file.readAsString(), 'unreadable journal');
  });

  test('synchronous factory failures also degrade to null', () async {
    expect(
      await optionalStartup<int>(() => throw StateError('factory')),
      isNull,
    );
  });
}
