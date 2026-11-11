import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  for (final style in ShareTemplateStyle.values) {
    testWidgets(
      'incoming $style template previews cancels and saves a new copy without changing defaults',
      (tester) async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final settings = ShareTemplateSettings(db);
        final original = ShareTemplate(
          id: 'original',
          name: 'Shared',
          style: style,
          body: '☕ <time> / <ratio>',
        );
        await settings.saveTemplate(original);
        await settings.select(style, original.id);
        final before = (await settings.load()).toJson();
        const channel = MethodChannel('holybeans/incoming');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'take' ? encodeShareTemplate(original) : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final incoming = IncomingShares();
        addTearDown(incoming.dispose);
        await tester.pumpWidget(
          HolyBeansApp(
            services: AppServices(database: db, incoming: incoming),
            initialLocale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ShareTemplateEditor), findsOneWidget);
        expect(find.text('Review template'), findsOneWidget);
        expect((await settings.load()).toJson(), before);
        final preview = find.byKey(const ValueKey('template-preview'));
        await tester.scrollUntilVisible(
          preview,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ShareTemplateEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester.widget<SelectableText>(preview).data,
          style == ShareTemplateStyle.espresso
              ? '☕ 0:28 / 1:2'
              : '☕ 3:00 / 1:16',
        );
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect((await settings.load()).toJson(), before);
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'holybeans/incoming',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('arrived', encodeShareTemplate(original)),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
        expect(find.byType(ShareTemplatesPage), findsOneWidget);
        expect(find.text('Templates'), findsOneWidget);
        final after = await settings.load();
        expect(after.templates, hasLength(2));
        expect(after.templates.last.id, isNot(original.id));
        expect(after.templates.last.body, original.body);
        expect(after.toJson()['defaults'], before['defaults']);
        expect(after.toJson()['fields'], before['fields']);
        expect(await db.select(db.brews).get(), isEmpty);
        expect(await db.select(db.coffees).get(), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }
}
