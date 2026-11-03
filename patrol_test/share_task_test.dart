import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_brew_flow.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_support.dart';

void main() {
  patrolTest(
    'brew shares open a separate receiving task and return without nested apps',
    tags: ['android', 'share-task'],
    ($) async {
      final db = await openTestDatabase();
      final directory = await Directory.systemTemp.createTemp('share-task-');
      final photos = PhotoStore(directory);
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        final coffeeId = await repo.createCoffee(
          name: 'Share test',
          roaster: 'Test',
        );
        final brewId = await repo.createBrew(
          coffeeId: coffeeId,
          methodName: 'V60',
          doseGrams: 18,
          waterGrams: 300,
        );
        final photo = await photos.add(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAJElEQVR4nGNYkGJEU8QwasGoBaMWjFowasGoBaMWjFowNCwAAOLyoi6oYjKmAAAAAElFTkSuQmCC',
          ),
        );
        await repo.setBrewPhotos(brewId, [photo]);
        final brew = (await repo.brew(brewId))!;
        final coffee = (await repo.coffee(coffeeId))!;
        var returns = 0;
        await $.pumpWidgetAndSettle(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Returns: $returns'),
                      TextButton(
                        onPressed: () async {
                          await shareBrewFlow(
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
                          );
                          if (context.mounted) setState(() => returns++);
                        },
                        child: const Text('Share brew'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final mode in ['text', 'image', 'caption', 'cancel']) {
          await $.tap(find.text('Share brew'));
          if (mode == 'image' || mode == 'caption') {
            await $.tap(find.text('Image'));
            if (mode == 'caption') {
              await $.tap(find.byKey(const ValueKey('share-photo-caption')));
            }
          }
          await $.tap(find.byKey(const ValueKey('share-confirm')));
          if (mode == 'cancel') {
            await $.platform.android.pressBack();
          } else {
            await _selectReceiver($);
            await $.platform.mobile.waitUntilVisible(
              Selector(text: 'Separate share task'),
            );
            if (mode != 'image') {
              await $.platform.mobile.waitUntilVisible(
                Selector(text: 'Text received'),
              );
            }
            if (mode != 'text') {
              await $.platform.mobile.waitUntilVisible(
                Selector(text: 'Image readable'),
              );
            }
            await $.takeNativeScreenshot('share-separate-task-$mode');
            await $.platform.android.pressBack();
          }
          await $.pumpAndSettle();
          await $.waitUntilVisible(find.text('Share brew'));
          expect(
            find.text(
              'Returns: ${['text', 'image', 'caption', 'cancel'].indexOf(mode) + 1}',
            ),
            findsOneWidget,
          );
        }
        expect(await repo.allBrews(), hasLength(1));
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<void> _selectReceiver(PatrolIntegrationTester $) async {
  // Samsung's target row can span several pages; its order is user-specific.
  for (var page = 0; page < 8; page++) {
    final receiver = await $.platform.android.getNativeViews(
      const AndroidSelector(text: 'HB Share Test'),
    );
    if (receiver.roots.isNotEmpty) {
      await $.platform.mobile.tap(Selector(text: 'HB Share Test'));
      return;
    }
    final more = await $.platform.android.getNativeViews(
      const AndroidSelector(text: 'More'),
    );
    if (more.roots.isNotEmpty) {
      await $.platform.mobile.tap(Selector(text: 'More'));
      await $.platform.mobile.tap(Selector(text: 'HB Share Test'));
      return;
    }
    await $.platform.android.swipe(
      from: const Offset(.9, .93),
      to: const Offset(.1, .93),
      steps: 80,
    );
  }
  fail('Local share receiver is not visible in the Android Sharesheet');
}
