import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_brew_flow.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/share_photo_card.dart';

void main() {
  for (final scenario in ['brew', 'coffee', 'missing', 'none']) {
    testWidgets(
      'share loads $scenario photo and allows camera/gallery replacement',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final directory = Directory.systemTemp.createTempSync(
          'share-photo-flow',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final photos = PhotoStore(directory);
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
        );
        // Different file bytes let the assertion distinguish the selected source.
        final coffeeBytes = [...bytes, 0];
        final coffeeId = await repo.createCoffee(
          name: 'Coffee',
          roaster: 'R',
          roastDate: '2024-02-28',
        );
        final lot = (await repo.coffeeLots(coffeeId)).single;
        final brewId = await repo.createBrew(
          coffeeId: coffeeId,
          lotId: lot.id,
          brewedAt: DateTime(2024, 3),
          methodName: 'V60',
        );
        await tester.runAsync(() async {
          if (scenario != 'none') {
            final name = await photos.add(Uint8List.fromList(coffeeBytes));
            await repo.setCoffeePhotos(coffeeId, [name]);
          }
          if (scenario == 'brew' || scenario == 'missing') {
            final name = await photos.add(bytes);
            await repo.setBrewPhotos(brewId, [name]);
            if (scenario == 'missing') await photos.delete(name);
          }
        });
        final coffee = (await repo.coffee(coffeeId))!;
        final brew = (await repo.brew(brewId))!;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => shareBrewFlow(
                    context,
                    repository: repo,
                    photos: photos,
                    settings: BrewParameterSettings(db),
                    templateSettings: ShareTemplateSettings(db),
                    brew: brew,
                    coffee: coffee,
                    components: const [],
                    method: null,
                    message: fail,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Open'));
          for (
            var i = 0;
            i < 1000 && find.byType(ShareBrewSheet).evaluate().isEmpty;
            i++
          ) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(
          tester.widget<ShareBrewSheet>(find.byType(ShareBrewSheet)).lot?.id,
          lot.id,
        );
        final initial = tester
            .widget<ShareBrewSheet>(find.byType(ShareBrewSheet))
            .initialPhoto;
        expect(
          initial,
          scenario == 'none'
              ? null
              : scenario == 'brew'
              ? bytes
              : coffeeBytes,
        );
        final s = lookupAppLocalizations(const Locale('en'));
        await tester.tap(find.text(s.shareFormatImage));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('share-photo-caption')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('share-choose-photo')),
            matching: find.text(initial == null ? s.addPhoto : s.changePhoto),
          ),
          findsOneWidget,
        );
        const channel = MethodChannel('plugins.flutter.io/image_picker');
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        for (final camera in [false, true]) {
          final change = find.byKey(const ValueKey('share-choose-photo'));
          await tester.ensureVisible(change);
          await tester.tap(change);
          await tester.pumpAndSettle();
          expect(find.text(s.takePhoto), findsOneWidget);
          expect(find.text(s.choosePhoto), findsOneWidget);
          await tester.tap(find.text(camera ? s.takePhoto : s.choosePhoto));
          await tester.pumpAndSettle();
          expect(calls.last.arguments['source'], camera ? 0 : 1);
          expect(
            tester.widget<SharePhotoCard>(find.byType(SharePhotoCard)).photo,
            initial,
          );
        }
        // Cancelling either native picker preserves the automatic photo.
        expect(
          await repo.brewPhotos(brewId),
          scenario == 'brew' || scenario == 'missing' ? hasLength(1) : isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
