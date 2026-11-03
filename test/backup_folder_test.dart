import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/backup_folder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'each platform write owns its source until that call finishes',
    () async {
      final dir = await Directory.systemTemp.createTemp('folder-write-test-');
      addTearDown(() => dir.delete(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const backups = MethodChannel('holybeans/backups');
      messenger.setMockMethodCallHandler(paths, (_) async => dir.path);
      final entered = [Completer<void>(), Completer<void>()];
      final release = [Completer<void>(), Completer<void>()];
      final sources = <File>[];
      messenger.setMockMethodCallHandler(backups, (call) async {
        if (call.method == 'list') return <String>[];
        if (call.method == 'write') {
          final args = call.arguments as Map<Object?, Object?>;
          final index = sources.length;
          sources.add(File(args['path']! as String));
          entered[index].complete();
          await release[index].future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(backups, null);
      });
      const folder = AndroidBackupFolder();
      final a = folder.save(
        'uri',
        Uint8List.fromList([1, 2, 3]),
        DateTime(2026, 10, 18),
      );
      await entered[0].future;
      final b = folder.save(
        'uri',
        Uint8List.fromList([4, 5, 6]),
        DateTime(2026, 10, 18),
      );
      await entered[1].future;
      expect(sources[0].path, isNot(sources[1].path));
      expect(await sources[0].readAsBytes(), [1, 2, 3]);
      expect(await sources[1].readAsBytes(), [4, 5, 6]);
      release[0].complete();
      await a;
      expect(sources[0].existsSync(), isFalse);
      expect(sources[1].existsSync(), isTrue);
      release[1].complete();
      await b;
      expect(sources[1].existsSync(), isFalse);
    },
  );
}
