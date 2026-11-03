import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_support.dart';

void main() {
  patrolTest(
    'brew clipboard pastes text and transparent PNG into another app',
    tags: ['android', 'clipboard'],
    ($) async {
      final db = await openTestDatabase();
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        final id = await repo.createCoffee(
          name: 'Clipboard test',
          roaster: 'Test',
        );
        final brewId = await repo.createBrew(
          coffeeId: id,
          methodName: 'V60',
          doseGrams: 18,
        );
        final coffee = (await repo.coffee(id))!;
        final brew = (await repo.brew(brewId))!;
        await $.pumpWidgetAndSettle(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ShareBrewSheet(
                coffee: coffee,
                brew: brew,
                components: const [],
                initialFields: const {BrewParameter.coffee, BrewParameter.dose},
              ),
            ),
          ),
        );
        final copy = find.byKey(const ValueKey('share-copy'));
        await $.tap(copy);
        await $.waitUntilVisible(find.text('Text copied'));
        final expected = $.tester
            .widget<SelectableText>(find.byType(SelectableText))
            .data!;
        expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, expected);
        await _pasteInReceiver($, 'Clipboard text: $expected');
        await $.platform.mobile.openApp();
        await $.pumpAndSettle();
        await $.tap(find.text('Image'));
        await $.tap(find.byKey(const ValueKey('share-transparent-background')));
        await $.tap(copy);
        await $.waitUntilVisible(find.text('Image copied'));
        await $.takeNativeScreenshot('brew-image-copied');
        await _pasteInReceiver($, 'Clipboard PNG readable with transparency');
        await $.takeNativeScreenshot('brew-clipboard-external-paste');
        await $.platform.mobile.openApp();
        await $.pumpAndSettle();
        expect(find.byType(ShareBrewSheet), findsOneWidget);
        expect(await repo.allBrews(), hasLength(1));
      } finally {
        await $.platform.mobile.openApp();
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
      }
    },
  );
}

Future<void> _pasteInReceiver(
  PatrolIntegrationTester $,
  String expected,
) async {
  await $.platform.mobile.openApp(
    appId: 'com.caffeinateddev.holybeans.patrol.test',
  );
  await $.platform.mobile.tap(Selector(text: 'Paste test clipboard'));
  await $.platform.mobile.waitUntilVisible(Selector(text: expected));
}
