import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });
  for (final language in ['es', 'en']) {
    final s = language == 'es' ? AppLocalizationsEs() : AppLocalizationsEn();
    testWidgets(
      'saved template edits and defaults remain separate by style ($language)',
      (tester) async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final settings = ShareTemplateSettings(db);
        await tester.pumpWidget(
          localizedApp(
            theme: AppTheme.light(),
            locale: Locale(language),
            home: ShareTemplatesPage(settings: settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.shareTemplateEmpty), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('template-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('template-name')),
          'My template',
        );
        await tester.enterText(
          find.byKey(const ValueKey('template-body')),
          '☕ <time> / <ratio>',
        );
        await tester.tap(find.text(s.save));
        await tester.pumpAndSettle();
        final template = (await settings.load()).templates.single;
        expect(template.body, '☕ <time> / <ratio>');
        // The card reads filled in with example values, the raw text below.
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('template-preview-${template.id}')),
              )
              .data,
          '☕ 0:28 / 1:2',
        );
        await tester.tap(
          find.byKey(ValueKey('template-default-${template.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          (await settings.load()).selected(ShareTemplateStyle.espresso)?.id,
          template.id,
        );
        await tester.tap(find.text(s.styleFilter));
        await tester.pumpAndSettle();
        expect(find.text('My template'), findsNothing);
        expect(find.text(s.shareTemplateEmpty), findsOneWidget);
        expect(
          (await settings.load()).selected(ShareTemplateStyle.filter),
          isNull,
        );
        await tester.tap(find.text(s.styleEspresso));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(s.shareTemplateEdit));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('template-body')),
          'Changed <time>',
        );
        await tester.tap(find.text(s.cancel));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('discard-changes')));
        await tester.pumpAndSettle();
        expect((await settings.load()).templates.single.body, template.body);
        await tester.tap(find.byTooltip(s.delete));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, s.delete));
        await tester.pumpAndSettle();
        expect(
          (await settings.load()).selected(ShareTemplateStyle.espresso),
          isNull,
        );
        expect(find.text(s.shareTemplateEmpty), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'editor inserts at cursor and validates unknown tags on narrow dark screen ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ShareTemplate? saved;
        await tester.pumpWidget(
          localizedApp(
            theme: AppTheme.dark(),
            locale: Locale(language),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFormSheet<ShareTemplate>(
                    context,
                    ShareTemplateEditor(
                      style: ShareTemplateStyle.espresso,
                      onSave: (value) async => saved = value,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('template-name')),
          'Example',
        );
        await tester.enterText(
          find.byKey(const ValueKey('template-body')),
          '<bogus>',
        );
        await tester.tap(find.text(s.save));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(find.text(s.shareTemplateInvalid), findsWidgets);
        final body = find.byKey(const ValueKey('template-body'));
        await tester.ensureVisible(body);
        await tester.enterText(body, '<country> ');
        final controller = tester.widget<TextFormField>(body).controller!;
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('template-tags')),
          180,
          scrollable: verticalScrollable(find.byType(ShareTemplateEditor)),
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text(s.shareTemplateTags)),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.shareTemplateTags));
        await tester.pumpAndSettle();
        final tag = find.byKey(const ValueKey('template-tag-country_flag'));
        await tester.scrollUntilVisible(
          tag,
          180,
          scrollable: verticalScrollable(find.byType(ShareTemplateEditor)),
        );
        await tester.ensureVisible(tag);
        await tester.pumpAndSettle();
        await tester.tap(tag);
        await tester.pumpAndSettle();
        expect(controller.text, '<country> <country_flag>');
        // The preview sits right under the text, above the tags.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('template-preview')),
          -180,
          scrollable: verticalScrollable(find.byType(ShareTemplateEditor)),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('template-preview')),
              )
              .data,
          'Colombia 🇨🇴',
        );
        await tester.tap(find.text(s.save));
        await tester.pumpAndSettle();
        expect(saved?.body, '<country> <country_flag>');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'template preview, text result and image use same content; fields remain available',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(
        name: 'Share coffee',
        roaster: 'R',
        roastDate: '2024-02-28',
      );
      final lot = (await repo.coffeeLots(id)).single;
      await repo.createBrew(
        coffeeId: id,
        lotId: lot.id,
        brewedAt: DateTime(2024, 3),
        methodName: 'Espresso',
        doseGrams: 18,
        beverageGrams: 36,
        timeSeconds: 28,
      );
      final coffee = await db.select(db.coffees).getSingle();
      final brew = await db.select(db.brews).getSingle();
      const template = ShareTemplate(
        id: 't',
        name: 'Story',
        style: ShareTemplateStyle.espresso,
        body: 'My brew <time> at <ratio>\nTDS <tds> / <cost> / <farm>\nRest <days_from_roast>',
      );
      ShareBrewResult? result;
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showFormSheet<ShareBrewResult>(
                      context,
                      ShareBrewSheet(
                        cost: 0.9,
                        lot: lot,
                        coffee: coffee,
                        brew: brew,
                        components: const [],
                        initialFields: const {BrewParameter.notes},
                        configuration: ShareConfiguration(
                          fields: {BrewParameter.notes},
                          templates: [template],
                          defaults: {ShareTemplateStyle.espresso: 't'},
                        ),
                      ),
                    ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('My brew 0:28 at 1:2\nTDS — / €0.90 / —\nRest 2'),
        findsOneWidget,
      );
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BrewShareCard>(find.byType(BrewShareCard)).customText,
        'My brew 0:28 at 1:2\nTDS — / €0.90 / —\nRest 2',
      );
      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-confirm')));
      await tester.pumpAndSettle();
      expect(result?.text, 'My brew 0:28 at 1:2\nTDS — / €0.90 / —\nRest 2');
      expect(result?.fields, {BrewParameter.notes});
      expect(result?.rememberFields, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
