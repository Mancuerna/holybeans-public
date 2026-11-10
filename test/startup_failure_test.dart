import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/startup/startup_recovery.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_startup.dart';

class CloseTracker extends QueryInterceptor {
  CloseTracker(this.fail);
  final bool fail;
  bool closed = false;
  @override
  Future<void> close(QueryExecutor inner) async {
    closed = true;
    await inner.close();
    if (fail) throw StateError('close failed');
  }
}

void main() {
  for (final failure in [
    'installation',
    'database',
    'photos',
    'recovery',
    'close',
  ]) {
    testWidgets(
      '$failure failure shows recovery before starting optional services',
      (tester) async {
        final tracker = CloseTracker(failure == 'close');
        final database = AppDatabase.forTesting(
          NativeDatabase.memory().interceptWith(tracker),
        );
        final directory = Directory.systemTemp.createTempSync(
          'startup-failure-',
        );
        final preserved = File(path.join(directory.path, 'existing-photo.jpg'))
          ..writeAsStringSync('preserved');
        final services = TestStartup(
          database,
          PhotoStore(directory),
          failure == 'close' ? 'recovery' : failure,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
        addTearDown(() async {
          messenger.setMockMethodCallHandler(paths, null);
          services.workingScale.dispose();
          if (!tracker.closed) await database.close();
          directory.deleteSync(recursive: true);
        });
        final app = await tester.runAsync(() => prepareApp(services: services));
        expect(app, isA<StartupRecoveryApp>());
        expect(
          tracker.closed,
          ['photos', 'recovery', 'close'].contains(failure),
        );
        for (final optional in [
          'backups',
          'reminders',
          'scale',
          'pressure',
          'refractometer',
          'drive',
        ]) {
          expect(services.started, isNot(contains(optional)));
        }
        await tester.pumpWidget(app!);
        await tester.pumpAndSettle();
        expect(find.text('Could not open your journal'), findsOneWidget);
        expect(preserved.readAsStringSync(), 'preserved');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
