import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/fake_scale.dart';

Future<void> checkShareTemplates(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final partial = await repo.createCoffeeWithComponents(
    name: 'Patrol partial frozen',
    roaster: 'Fixture',
    components: const [CoffeeComponentInput(country: 'Colombia')],
    initialGrams: 100,
    freeze: const FreezeRequest(grams: 30, frozenDate: '2026-10-01'),
  );
  await repo.createCoffeeWithComponents(
    name: 'Patrol all frozen',
    roaster: 'Fixture',
    components: [],
    initialGrams: 100,
    freeze: const FreezeRequest(grams: 100, frozenDate: '2026-10-01'),
  );
  final method = await repo.createMethod(
    name: 'Espresso',
    category: 'espresso',
  );
  await repo.createBrew(
    coffeeId: partial,
    methodId: method,
    methodName: 'Espresso',
    doseGrams: 18,
    beverageGrams: 36,
    timeSeconds: 28,
    temperatureC: 93,
  );
  final fields = BrewParameterSettings(database);
  await fields.saveShared({BrewParameter.coffee, BrewParameter.time});
  final settings = ShareTemplateSettings(database);
  final scale = FakeScale();
  String? sharedText;
  int? imageLength;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        sharedText = args['text'] as String?;
        if (args['paths'] case final List<dynamic> paths) {
          imageLength = (await File(
            paths.single as String,
          ).readAsBytes()).length;
        }
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
  Future<void> tab(String text) => $.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(text)),
  );
  Future<void> openShare() async {
    await $.tap(find.byTooltip('Actions'));
    await $.tap(find.text('Share brew'));
    await $.waitUntilVisible(find.byType(ShareBrewSheet));
  }

  Future<void> addTemplate(String name, String body) async {
    await $.tap(find.byKey(const ValueKey('template-add')));
    await $.enterText(find.byKey(const ValueKey('template-name')), name);
    await $.enterText(find.byKey(const ValueKey('template-body')), body);
    await $.takeNativeScreenshot('template-editor-$name');
    await $.tap(find.text('Save').last);
    await $.waitUntilVisible(find.text(name));
    final template = (await settings.load()).templates.firstWhere(
      (t) => t.name == name,
    );
    await $.tap(find.byKey(ValueKey('template-default-${template.id}')));
  }

  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        services: AppServices(database: database, scale: scale),
        initialLocale: const Locale('en'),
      ),
    );
    await tab('Beans');
    // Frozen badges were renamed in the 15 October interface review.
    await $.waitUntilVisible(find.text('Part'));
    await $.takeNativeScreenshot('accents-partial-frozen');
    await $.tap(find.text('Frozen (2)'));
    await $.waitUntilVisible(find.text('Frozen').first);
    await $.takeNativeScreenshot('accents-all-frozen');
    await tab('Brews');
    await $.tap(find.text('Brew').last);
    await $.tap(find.byKey(const ValueKey('brew-coffee-picker')));
    await $.waitUntilVisible(find.text('Patrol all frozen').last);
    await $.takeNativeScreenshot('accents-coffee-picker');
    await $.tap(find.text('Patrol partial frozen').last);
    await $.tap(find.text('Cancel').last);
    final discard = find.byKey(const ValueKey('discard-changes'));
    if (discard.evaluate().isNotEmpty) await $.tap(discard);
    await $.tap(find.byTooltip('Settings'));
    await $.takeNativeScreenshot('accents-settings');
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('settings-scale')),
    );
    await $.tap(find.byKey(const ValueKey('settings-scale')));
    await $.waitUntilVisible(find.byKey(const ValueKey('scale-find')));
    expect(scale.commands, isEmpty);
    await $.tap(find.byType(BackButton));
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('share-templates')),
      scrollDirection: AxisDirection.up,
    );
    await $.tap(find.byKey(const ValueKey('share-templates')));
    await addTemplate(
      'Espresso-story',
      '<country_flag> <country>: My brew <time> at <ratio> and <brew_temp>.',
    );
    await $.tap(find.text('Filter'));
    await addTemplate('Filter-story', '<coffee>: <water> in <time>.');
    expect(
      (await settings.load()).selected(ShareTemplateStyle.espresso)?.name,
      'Espresso-story',
    );
    expect(
      (await settings.load()).selected(ShareTemplateStyle.filter)?.name,
      'Filter-story',
    );
    await $.takeNativeScreenshot('template-filter-saved');
    await $.tap(find.byType(BackButton));
    await $.tap(find.byType(BackButton));
    await openShare();
    await $.waitUntilVisible(
      find.text('🇨🇴 Colombia: My brew 0:28 at 1:2 and 93 °C.'),
    );
    await $.takeNativeScreenshot('template-share-preview');
    await $.tap(find.byKey(const ValueKey('share-confirm')));
    await $.pumpAndSettle();
    expect(sharedText, '🇨🇴 Colombia: My brew 0:28 at 1:2 and 93 °C.');
    await openShare();
    await $.tap(find.text('Image'));
    await $.takeNativeScreenshot('template-share-image');
    await $.tap(find.byKey(const ValueKey('share-confirm')));
    await $.pumpAndSettle();
    expect(imageLength, greaterThan(0));
    await openShare();
    await $.tap(find.byType(DropdownButtonFormField<String>));
    await $.tap(find.text('Field format').last);
    await $.waitUntilVisible(
      find.textContaining('Coffee name: Patrol partial frozen'),
    );
    await $.takeNativeScreenshot('template-original-fields');
    await $.tap(find.byKey(const ValueKey('share-confirm')));
    await $.pumpAndSettle();
    expect(sharedText, contains('Coffee name: Patrol partial frozen'));
    expect(await fields.loadShared(), {
      BrewParameter.coffee,
      BrewParameter.time,
    });
    expect((await database.select(database.brews).get()).length, 1);
    expect((await repo.coffeeLots(partial)).single.remainingGrams, 70);
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    scale.dispose();
  }
}
