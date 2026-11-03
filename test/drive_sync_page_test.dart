@Tags(['slow'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_page.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';
import 'package:path/path.dart' as path;

import 'helpers/drive_fake_server.dart';

Future<void> _waitForIdle(DriveSyncModel model) => Future.doWhile(() async {
  if (!model.busy) return false;
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return true;
}).timeout(const Duration(seconds: 30));

// SQLite transaction callbacks can be queued in the widget clock while Drive
// reads real files. Advance both clocks until the requested operation finishes.
Future<void> _runAndPump(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var finished = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    action().then(
      (_) => finished = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        finished = true;
      },
    ),
  );
  final watch = Stopwatch()..start();
  while (!finished && watch.elapsed < const Duration(seconds: 40)) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(finished, isTrue, reason: 'Drive UI operation did not finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late Directory directory;
  late DriveSyncModel model;
  late DriveFakeServer server;
  const channel = MethodChannel('holybeans/drive-sync');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drive-ui-');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    model = await DriveSyncModel.open(
      JournalBackup(database),
      PhotoStore(Directory(path.join(directory.path, 'photos'))),
    );
    server = DriveFakeServer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, server.handle);
  });
  tearDown(() async {
    model.dispose();
    await _waitForIdle(model);
    await database.close();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'offline backups never prevent edits; later copy contains them',
    () async {
      await model.enable();
      server.offline = true;
      await JournalRepository(database)
          .createCoffee(name: 'Offline', roaster: 'Test');
      await model.synchronize();
      expect(model.status, DriveSyncStatus.unavailable);
      expect(database.writeGate.writable, isTrue);
      await JournalRepository(database)
          .createCoffee(name: 'Still editable', roaster: 'Test');
      server.offline = false;
      await model.synchronize();
      await model.refreshCopies();
      expect(model.copies.length, 2);
      final service = DriveRemoteAdapter(
        accountKey: model.account!,
        client: model.client,
        backupMode: true,
        payloads: DriveSyncPayloadStore(
          Directory(path.join(directory.path, 'verify')),
        ),
        photoQueue: AtomicJsonFile(
          File(path.join(directory.path, 'verify-photos.json')),
        ),
      );
      await service.download(model.copies.first.snapshot);
      final payload = await service.payloads.read(
        model.copies.first.snapshot.id,
      );
      expect(
        ((jsonDecode(payload.source) as Map)['data'] as Map)['coffees'],
        hasLength(2),
      );
    },
  );

  test('uncertain upload survives restart without duplicating it', () async {
    server.loseNextUpload = true;
    await model.enable();
    expect(model.status, DriveSyncStatus.unavailable);
    expect(server.files, hasLength(1));
    model.dispose();
    model = await DriveSyncModel.open(JournalBackup(database), model.photos);
    expect(database.writeGate.writable, isTrue);
    await model.synchronize();
    expect(model.status, DriveSyncStatus.current);
    expect(server.files, hasLength(1));
    expect(model.lastBackupAt, isNotNull);
  });

  test(
    'five copies per device; another device is never overwritten or applied',
    () async {
      await model.enable();
      final otherDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      final other = await DriveSyncModel.open(
        JournalBackup(otherDatabase),
        PhotoStore(Directory(path.join(directory.path, 'other', 'photos'))),
      );
      try {
        await JournalRepository(otherDatabase)
            .createCoffee(name: 'Other phone', roaster: 'Test');
        await other.enable();
        for (var i = 0; i < 6; i++) {
          await JournalRepository(database)
              .createCoffee(name: 'Coffee $i', roaster: 'Test');
          await model.synchronize();
        }
        await model.refreshCopies();
        expect(
          model.copies.where((c) => c.snapshot.deviceId == model.deviceId),
          hasLength(5),
        );
        expect(
          model.copies.where((c) => c.snapshot.deviceId == other.deviceId),
          hasLength(1),
        );
        await other.synchronize();
        expect(
          (await otherDatabase.select(otherDatabase.coffees).get()).single.name,
          'Other phone',
        );
        expect(await database.select(database.coffees).get(), hasLength(6));
      } finally {
        other.dispose();
        await otherDatabase.close();
      }
    },
  );

  test('legacy config migrates, old copies restore explicitly with safety copy and photos', () async {
    final repo = JournalRepository(database);
    final id = await repo.createCoffee(name: 'Old journal', roaster: 'Test');
    final photo = await model.photos.add(Uint8List.fromList([1, 2, 3, 4]));
    await repo.setCoffeePhotos(id, [photo]);
    final payloads = DriveSyncPayloadStore(
      Directory(path.join(directory.path, 'legacy')),
    );
    final payload = await DriveSyncPayload.prepare(
      await model.backup.exportJson(),
      await model.photos.readAll(),
    );
    final legacy = DriveRemoteAdapter(
      accountKey: 'a' * 64,
      client: model.client,
      payloads: payloads,
      photoQueue: AtomicJsonFile(
        File(path.join(directory.path, 'legacy-photos.json')),
      ),
    );
    final snapshot = DriveSnapshot(
      id: await legacy.reserveId(),
      deviceId: 'old-phone',
      contentHash: payload.hash,
    );
    await payloads.write(snapshot.id, payload);
    await legacy.publish(snapshot);
    await model.config.write({
      'version': 1,
      'device': model.deviceId,
      'account': 'a' * 64,
      'enabled': true,
    });
    model.dispose();
    model = await DriveSyncModel.open(JournalBackup(database), model.photos);
    expect(database.writeGate.writable, isTrue);
    await repo.createCoffee(name: 'Local addition', roaster: 'Test');
    await model.synchronize();
    expect(await database.select(database.coffees).get(), hasLength(2));
    await model.refreshCopies();
    final old = model.copies.singleWhere((c) => c.legacy);
    await model.restore(old);
    expect(
      (await database.select(database.coffees).get()).single.name,
      'Old journal',
    );
    expect(await model.photos.file(photo).readAsBytes(), [1, 2, 3, 4]);
    expect(database.writeGate.writable, isTrue);
    final safety = await Directory(
      path.join(directory.path, 'drive-sync', 'safety'),
    ).list().toList();
    final saved = JournalBackup.readArchive(
      await (safety.single as File).readAsBytes(),
    );
    expect(
      ((jsonDecode(saved.$1) as Map)['data'] as Map)['coffees'],
      hasLength(2),
    );
    expect(saved.$2[photo], [1, 2, 3, 4]);
    expect(server.files.containsKey(snapshot.id), isTrue);
  });

  test(
    'corrupt configuration leaves the diary writable and original file intact',
    () async {
      await model.config.write({'version': 999});
      model.dispose();
      model = await DriveSyncModel.open(JournalBackup(database), model.photos);
      expect(model.enabled, isFalse);
      expect(await model.config.read(), {'version': 999});
      await JournalRepository(database)
          .createCoffee(name: 'Writable', roaster: 'Test');
    },
  );

  test('edits alone do not upload; lifecycle makes the next copy', () async {
    await model.enable();
    await JournalRepository(database)
        .createCoffee(name: 'Later', roaster: 'Test');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.files, hasLength(1));
    model.lifecycle(AppLifecycleState.paused);
    await _waitForIdle(model);
    expect(server.files, hasLength(2));
    final completed = model.lastBackupAt;
    await model.synchronize();
    expect(server.files, hasLength(2));
    expect(model.lastBackupAt, completed);
    await model.disable();
    model.lifecycle(AppLifecycleState.paused);
    expect(model.busy, isFalse);
  });

  for (final locale in ['es', 'en']) {
    testWidgets('rating saves during a stalled backup and offline in $locale', (
      tester,
    ) async {
      final repo = JournalRepository(database);
      final id = await repo.createCoffee(name: 'Fresh', roaster: 'Test');
      await repo.createBrew(coffeeId: id, methodName: 'V60', doseGrams: 18);
      final brew = await database.select(database.brews).getSingle();
      await _runAndPump(tester, model.enable);
      final strings = await AppLocalizations.delegate.load(Locale(locale));
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => DriveSyncScope(
            model: model,
            child: DriveSyncNotice(model: model, child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showRateBrewSheet(context, repo, brew, title: 'Fresh'),
                child: const Text('Rate'),
              ),
            ),
          ),
        ),
      );
      final held = Completer<void>();
      final entered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'connect') {
              if (!entered.isCompleted) entered.complete();
              await held.future;
            }
            return server.handle(call);
          });
      final operation = model.synchronize();
      await _runAndPump(tester, () => entered.future);
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.save));
      await tester.pumpAndSettle();
      expect(find.text('Rate'), findsOneWidget);
      expect(model.busy, isTrue);
      expect(database.writeGate.writable, isTrue);
      server.offline = true;
      held.complete();
      await _runAndPump(tester, () => operation);
      expect(model.status, DriveSyncStatus.unavailable);
      expect(find.text(strings.driveSyncUnavailable), findsNothing);
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.save));
      await tester.pumpAndSettle();
      expect(find.text('Rate'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'backup controls, last success and disable confirmation in $locale',
      (tester) async {
        final strings = await AppLocalizations.delegate.load(Locale(locale));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DriveSyncPage(model: model),
          ),
        );
        await _runAndPump(tester, model.enable);
        await tester.pumpAndSettle();
        expect(find.text(strings.driveSyncCurrent), findsOneWidget);
        expect(model.lastBackupAt, isNotNull);
        await tester.ensureVisible(find.text(strings.driveSyncDisable));
        await tester.tap(find.text(strings.driveSyncDisable));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.driveSyncCancel));
        await tester.pumpAndSettle();
        expect(model.enabled, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'edits during an upload remain pending for the next lifecycle',
    () async {
      await model.enable();
      await JournalRepository(database)
          .createCoffee(name: 'Captured', roaster: 'Test');
      final held = Completer<void>();
      final entered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'request' &&
                (call.arguments as Map)['method'] == 'PUT') {
              if (!entered.isCompleted) entered.complete();
              await held.future;
            }
            return server.handle(call);
          });
      final uploading = model.synchronize();
      await entered.future;
      await JournalRepository(database)
          .createCoffee(name: 'During upload', roaster: 'Test');
      held.complete();
      await uploading;
      expect(model.status, DriveSyncStatus.pending);
      model.lifecycle(AppLifecycleState.paused);
      await _waitForIdle(model);
      expect(model.status, DriveSyncStatus.current);
      await model.refreshCopies();
      await JournalRepository(database)
          .createCoffee(name: 'After copy', roaster: 'Test');
      await model.restore(model.copies.first);
      expect(
        (await database.select(database.coffees).get()).map((c) => c.name),
        containsAll(['Captured', 'During upload']),
      );
      expect(await database.select(database.coffees).get(), hasLength(2));
      expect(model.status, DriveSyncStatus.pending);
    },
  );

  test(
    'corrupt remote copy cannot replace local data or leave the gate closed',
    () async {
      await JournalRepository(database)
          .createCoffee(name: 'Keep me', roaster: 'Test');
      await model.enable();
      await model.refreshCopies();
      final copy = model.copies.first;
      server.files[copy.snapshot.id]!.bytes = Uint8List.fromList([0, 1, 2]);
      await model.restore(copy);
      expect(model.status, DriveSyncStatus.unavailable);
      expect(database.writeGate.writable, isTrue);
      expect(model.restoring, isFalse);
      expect(
        (await database.select(database.coffees).get()).single.name,
        'Keep me',
      );
    },
  );

  test(
    'missing referenced photo rejects a copy but allows further journal saves',
    () async {
      await model.enable();
      final repo = JournalRepository(database);
      final id = await repo.createCoffee(name: 'Photo', roaster: 'Test');
      final photo = await model.photos.add(Uint8List.fromList([1, 2, 3]));
      await repo.setCoffeePhotos(id, [photo]);
      await model.photos.delete(photo);
      await model.synchronize();
      expect(model.status, DriveSyncStatus.unavailable);
      expect(server.files, hasLength(1));
      await repo.createCoffee(name: 'Next', roaster: 'Test');
      expect(await database.select(database.coffees).get(), hasLength(2));
    },
  );

  test('silent authorization timeout never closes write access; manual retry reauthorizes', () async {
    await model.enable();
    model.connectTimeout = const Duration(milliseconds: 20);
    final stalled = Completer<void>();
    var cancelled = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') {
            cancelled++;
            stalled.complete();
            return null;
          }
          if (call.method == 'connect' &&
              (call.arguments as Map)['interactive'] == false) {
            await stalled.future;
          }
          return server.handle(call);
        });
    await model.synchronize();
    expect(cancelled, 1);
    expect(model.status, DriveSyncStatus.unavailable);
    await JournalRepository(database)
        .createCoffee(name: 'No wait', roaster: 'Test');
    await model.synchronize(interactive: true);
    expect(model.status, DriveSyncStatus.current);
  });
}
