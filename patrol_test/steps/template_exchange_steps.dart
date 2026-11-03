import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:patrol/patrol.dart';

Future<void> checkTemplateExchange(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final settings = ShareTemplateSettings(db);
  const template = ShareTemplate(
    id: 'local-template',
    name: 'Patrol shared recipe',
    style: ShareTemplateStyle.espresso,
    body: 'Mi <coffee> salió en <time>, ratio <ratio> y <brew_temp>.',
  );
  await settings.saveTemplate(template);
  await settings.select(template.style, template.id);
  final before = (await settings.load()).toJson();
  String? exported;
  const sharing = MethodChannel('dev.fluttercommunity.plus/share');
  const incomingChannel = MethodChannel('holybeans/incoming');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(sharing, (call) async {
    final args = call.arguments as Map;
    final files = args['paths'] as List;
    exported = await File(files.single as String).readAsString();
    return 'dev.fluttercommunity.plus/share/unavailable';
  });
  final incoming = IncomingShares();
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        database: db,
        initialLocale: const Locale('es'),
        incoming: incoming,
      ),
    );
    final context = $.tester.element(find.byType(NavigationBar));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShareTemplatesPage(settings: settings),
      ),
    );
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('template-menu-local-template')));
    await $.tap(find.text('Compartir plantilla'));
    await $.pumpAndSettle();
    expect(exported, isNotNull);
    expect(exported, isNot(contains('local-template')));
    expect(decodeShareTemplate(exported!, newId: 'new').body, template.body);
    expect((await settings.load()).toJson(), before);
    Navigator.of($.tester.element(find.byType(ShareTemplatesPage))).pop();
    await $.pumpAndSettle();
    Future<void> deliver() async {
      await messenger.handlePlatformMessage(
        'holybeans/incoming',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('arrived', exported),
        ),
        (_) {},
      );
      await $.pumpAndSettle();
      await $.waitUntilVisible(find.text('Revisar plantilla'));
    }

    await deliver();
    await $.takeNativeScreenshot('template-import-review');
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('template-preview')),
      view: find
          .descendant(
            of: find.byType(ShareTemplateEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await $.takeNativeScreenshot('template-import-preview');
    expect((await settings.load()).toJson(), before);
    await $.tap(find.text('Cancelar').last);
    expect((await settings.load()).toJson(), before);
    await deliver();
    await $.enterText(
      find.byKey(const ValueKey('template-name')),
      'Receta recibida',
    );
    await $.tap(find.text('Guardar').last);
    await $.pumpAndSettle();
    final after = await settings.load();
    expect(after.templates, hasLength(2));
    expect(after.templates.last.id, isNot(template.id));
    expect(after.templates.last.name, 'Receta recibida');
    expect(after.templates.last.body, template.body);
    expect(after.toJson()['defaults'], before['defaults']);
    expect(after.toJson()['fields'], before['fields']);
    await $.waitUntilVisible(find.byType(ShareTemplatesPage));
    await $.takeNativeScreenshot('template-import-saved');
    expect(await db.select(db.brews).get(), isEmpty);
    expect(await db.select(db.coffees).get(), isEmpty);
  } finally {
    messenger.setMockMethodCallHandler(sharing, null);
    messenger.setMockMethodCallHandler(incomingChannel, null);
    incoming.dispose();
  }
}
