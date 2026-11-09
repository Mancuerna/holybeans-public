import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));
  const espresso = ShareTemplate(
    id: 'espresso',
    name: 'Mi espresso',
    style: ShareTemplateStyle.espresso,
    body: '<country_flag> <country> <coffee>: <time> <ratio> <brew_temp>',
  );
  const filter = ShareTemplate(
    id: 'filter',
    name: 'Mi filtro',
    style: ShareTemplateStyle.filter,
    body: '<water> en <time>',
  );

  test('renders units, repeated tags, line breaks and unicode without evaluating values', () {
    expect(
      TemplateEngine.render('☕ <coffee>\n<time> / <time> <brew_temp>', {
        'coffee': 'Coffee <time>',
        'time': '0:28',
        'brew_temp': '93 °C',
      }),
      '☕ Coffee <time>\n0:28 / 0:28 93 °C',
    );
  });
  test(
    'missing is never zero; unknown tags remain visible and fail validation',
    () {
      expect(
        TemplateEngine.render('<tds> <time> <unknown> 2 < 3', {'time': ''}),
        '— — <unknown> 2 < 3',
      );
      expect(
        TemplateEngine.missingTags('<tds> <time> <unknown>', {'time': '0:00'}),
        {'tds'},
      );
      expect(TemplateEngine.unknownTags('<Time> <bad> <time>'), {
        'Time',
        'bad',
      });
      expect(
        () => const ShareTemplate(
          id: 'bad',
          name: 'Bad',
          style: ShareTemplateStyle.filter,
          body: '<bad>',
        ).validate(),
        throwsFormatException,
      );
    },
  );
  test(
    'country flags recognise aliases, keep blend order and skip unknowns',
    () {
      expect(
        shareTemplateCountryFlags([
          ' Etiopía ',
          'ET',
          'Colombia',
          'CO',
          null,
          'Atlantis',
        ]),
        '🇪🇹 🇨🇴',
      );
      expect(shareTemplateCountryFlags(['Kenya', 'Kenia', 'KE']), '🇰🇪');
      expect(shareTemplateCountryFlags(['Brasil', 'Brazil', 'BR']), '💀');
      expect(shareTemplateCountryFlags([null, '', 'Atlantis']), '');
      expect(
        TemplateEngine.render('<country_flag> <country>', {
          'country_flag': '🇨🇴',
          'country': 'Colombia',
        }),
        '🇨🇴 Colombia',
      );
      expect(
        TemplateEngine.render('<country_flag>', {'country_flag': ''}),
        '—',
      );
    },
  );

  test('legacy field choices remain exact and have no default templates', () {
    final old = ShareConfiguration.decode(
      jsonEncode(encodeSharedParameters({BrewParameter.notes})),
    );
    expect(old.fields, {BrewParameter.notes});
    expect(old.templates, isEmpty);
    expect(old.selected(ShareTemplateStyle.espresso), isNull);
    final initial = ShareConfiguration.decode(null).fields;
    for (final personal in [
      BrewParameter.date,
      BrewParameter.rating,
      BrewParameter.notes,
    ]) {
      expect(initial, isNot(contains(personal)));
    }
  });
  test(
    'templates, defaults and field choices survive backup and restore',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      final fields = BrewParameterSettings(db);
      await fields.saveShared({BrewParameter.notes, BrewParameter.time});
      await settings.saveOverlayBackgroundOpacity(0.75);
      await settings.saveTemplate(espresso);
      await settings.saveTemplate(filter);
      await settings.select(ShareTemplateStyle.espresso, espresso.id);
      await settings.select(ShareTemplateStyle.filter, filter.id);
      await fields.saveHidden({BrewParameter.pressure});
      final json = await JournalBackup(db).exportJson();
      await settings.deleteTemplate(espresso.id);
      await JournalBackup(db).restoreJson(json);
      final restored = await settings.load();
      expect(restored.overlayBackgroundOpacity, 0.75);
      expect(restored.fields, {BrewParameter.notes, BrewParameter.time});
      expect(restored.templates.map((t) => t.body), [
        espresso.body,
        filter.body,
      ]);
      expect(restored.selected(ShareTemplateStyle.espresso)?.id, espresso.id);
      expect(restored.selected(ShareTemplateStyle.filter)?.id, filter.id);
      expect(await fields.loadHidden(), {BrewParameter.pressure});
    },
  );
  test(
    'editing and removing templates retain the other style and shared fields',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      await settings.saveTemplate(espresso);
      await settings.saveTemplate(filter);
      await settings.select(ShareTemplateStyle.espresso, espresso.id);
      await settings.select(ShareTemplateStyle.filter, filter.id);
      await settings.saveTemplate(
        const ShareTemplate(
          id: 'espresso',
          name: 'Edited',
          style: ShareTemplateStyle.espresso,
          body: '<time>!',
        ),
      );
      expect(
        (await settings.load()).selected(ShareTemplateStyle.espresso)?.body,
        '<time>!',
      );
      await settings.deleteTemplate(espresso.id);
      final config = await settings.load();
      expect(config.selected(ShareTemplateStyle.espresso), isNull);
      expect(config.selected(ShareTemplateStyle.filter)?.id, filter.id);
      await expectLater(
        settings.select(ShareTemplateStyle.espresso, filter.id),
        throwsArgumentError,
      );
    },
  );
  test(
    'concurrent field and template saves do not overwrite one another',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      await Future.wait([
        settings.saveTemplate(espresso),
        settings.saveOverlayBackgroundOpacity(0.25),
        BrewParameterSettings(db).saveShared({BrewParameter.dose}),
        LanguageSetting(db).save(const Locale('es')),
      ]);
      final config = await settings.load();
      expect(config.overlayBackgroundOpacity, 0.25);
      expect(config.fields, {BrewParameter.dose});
      expect(config.templates.single.body, espresso.body);
      expect(await LanguageSetting(db).load(), const Locale('es'));
    },
  );
  test(
    'real espresso and filter tags use their own ratio and localized values',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffeeId = await repo.createCoffee(
        name: 'Coffee',
        roaster: 'Roaster',
      );
      final espressoId = await repo.createMethod(
        name: 'Machine',
        category: 'espresso',
      );
      await repo.createBrew(
        coffeeId: coffeeId,
        methodId: espressoId,
        methodName: 'Machine',
        doseGrams: 18,
        waterGrams: 288,
        beverageGrams: 36,
        timeSeconds: 28,
        temperatureC: 93.5,
      );
      final coffee = await db.select(db.coffees).getSingle();
      final brew = await db.select(db.brews).getSingle();
      final method = await db.select(db.brewMethods).getSingle();
      final values = shareTemplateValues(
        strings: AppLocalizationsEs(),
        coffee: coffee,
        brew: brew,
        components: [],
        method: method,
      );
      expect(values['ratio'], '1:2');
      expect(values['brew_temp'], '93.5 °C');
      expect(values['time'], '0:28');
      expect(values['tds'], '');
      expect(values['country_flag'], '');
      final origins = shareTemplateValues(
        strings: AppLocalizationsEs(),
        coffee: coffee,
        brew: brew,
        components: [
          CoffeeComponent(
            id: 'a',
            coffeeId: coffeeId,
            country: 'Colombia',
            position: 0,
          ),
          CoffeeComponent(
            id: 'b',
            coffeeId: coffeeId,
            country: 'Etiopía',
            position: 1,
          ),
          CoffeeComponent(
            id: 'c',
            coffeeId: coffeeId,
            country: 'Colombia',
            position: 2,
          ),
        ],
      );
      expect(origins['country_flag'], '🇨🇴 🇪🇹');
      expect(origins['country'], 'Colombia, Etiopía, Colombia');
      final filterValues = shareTemplateValues(
        strings: AppLocalizationsEs(),
        coffee: coffee,
        brew: brew.copyWith(methodName: 'V60'),
        components: [],
      );
      expect(filterValues['ratio'], '1:16');
    },
  );
}
