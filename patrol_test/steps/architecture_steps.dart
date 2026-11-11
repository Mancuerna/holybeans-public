import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// Real image picker cancellation and complete restore on Android storage.
Future<void> checkArchitectureFlows(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(path.join(support.path, 'architecture-photos'));
  if (directory.existsSync()) await directory.delete(recursive: true);
  final photos = PhotoStore(directory);
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Architecture original',
    roaster: 'Fixture',
  );
  final name = await photos.add(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    ),
  );
  await repo.setCoffeePhotos(coffee, [name]);
  final archive = await JournalBackup(db).exportArchive(photos);
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: db, photos: photos),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Add bean'));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Coffee name'),
    'Architecture draft',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('add-photo')),
    view: verticalScrollable(find.byType(CoffeeForm)),
  );
  await $.tap(find.byKey(const ValueKey('add-photo')));
  await $.waitUntilVisible(find.text('Choose from gallery'));
  expect(
    $.tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save').last)
        .onPressed,
    isNull,
  );
  await $.takeNativeScreenshot('architecture-photo-selection-busy');
  await $.tap(find.text('Choose from gallery'));
  await $.takeNativeScreenshot('architecture-native-photo-picker');
  // Android owns this picker; cancelling returns no filename to the form.
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byType(CoffeeForm));
  for (var i = 0; i < 100; i++) {
    final save = $.tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save').last,
    );
    if (save.onPressed != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await $.pump();
  }
  expect(
    $.tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save').last)
        .onPressed,
    isNotNull,
  );
  await $.tap(find.text('Cancel'));
  await $.tap(find.byKey(const ValueKey('discard-changes')));
  expect(await repo.allCoffees(), hasLength(1));
  expect(await photos.names(), {name});

  await repo.createCoffee(name: 'Architecture changed', roaster: 'Fixture');
  await photos.delete(name);
  await JournalBackup(db).restoreArchive(archive, photos);
  await $.pumpAndSettle();
  expect((await repo.allCoffees()).single.id, coffee);
  expect(await repo.coffeePhotos(coffee), [name]);
  expect(
    await photos.file(name).readAsBytes(),
    JournalBackup.readArchive(archive).$2[name],
  );
  await $.waitUntilVisible(find.text('Architecture original'));
  await $.tap(find.text('Architecture original'));
  await $.waitUntilVisible(find.byKey(const ValueKey('detail-photo')));
  await $.takeNativeScreenshot('architecture-restored-photo');
  expect(Directory('${directory.path}.restore').existsSync(), isFalse);
}
