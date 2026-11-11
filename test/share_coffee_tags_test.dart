import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });
  late AppDatabase db;
  late JournalRepository repo;
  late Coffee coffee;
  late Brew brew;
  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    final id = await repo.createCoffee(
      name: 'Blend',
      roaster: 'Roaster',
      initialGrams: 250,
      paidPriceCents: 1250,
      roastLevel: 'light',
      flavorProfile: 'Jasmine, cocoa',
    );
    await repo.createBrew(coffeeId: id, methodName: 'V60', doseGrams: 18);
    coffee = await repo.coffee(id) ?? (throw StateError('Missing coffee'));
    brew = await db.select(db.brews).getSingle();
  });
  tearDown(() => db.close());

  for (final s in [AppLocalizationsEs(), AppLocalizationsEn()]) {
    test('coffee tags preserve both origins and regional cost (${s.localeName})', () async {
      final components = [
        CoffeeComponent(
          id: 'a',
          coffeeId: coffee.id,
          position: 0,
          farm: 'La Colina',
          producer: 'Ana',
          altitudeMeters: 1500,
          altitudeMaxMeters: 1800,
          harvest: '2025/26',
        ),
        CoffeeComponent(
          id: 'b',
          coffeeId: coffee.id,
          position: 1,
          farm: 'El Roble',
          producer: 'Luis',
          altitudeMeters: 1900,
          harvest: '2026',
        ),
      ];
      final cost = brewCost(
        brew,
        pricePerKgByCoffee([coffee], await repo.watchLots().first),
      );
      final values = shareTemplateValues(
        strings: s,
        coffee: coffee,
        brew: brew,
        components: components,
        cost: cost,
      );
      expect(values['farm'], 'La Colina, El Roble');
      expect(values['producer'], 'Ana, Luis');
      expect(values['altitude'], '1500–1800 m, 1900 m');
      expect(values['harvest'], '2025/26, 2026');
      expect(values['roast_level'], s.roastLight);
      expect(values['flavor_notes'], 'Jasmine, cocoa');
      expect(values['cost'], '€0.90');
      const body =
          '<farm> / <producer> / <altitude> / <harvest> / <roast_level> / <flavor_notes> / <cost>';
      expect(TemplateEngine.unknownTags(body), isEmpty);
      expect(TemplateEngine.missingTags(body, values), isEmpty);
      final sections = BrewShareText.buildSections(
        strings: s,
        coffee: coffee,
        components: components,
        brew: brew,
        cost: cost,
        fields: {
          BrewParameter.farm,
          BrewParameter.producer,
          BrewParameter.cost,
        },
      );
      expect(sections.expand((rows) => rows).map((row) => row.$2), [
        'La Colina',
        'Ana',
        'El Roble',
        'Luis',
        values['cost'],
      ]);
    });
  }
  test(
    'new tags round-trip in a template file without changing field choices',
    () {
      const template = ShareTemplate(
        id: 'original',
        name: 'Origin and cost',
        style: ShareTemplateStyle.filter,
        body: '<farm> <producer> <altitude> <harvest> <roast_level> <flavor_notes> <cost>',
      );
      final restored = decodeShareTemplate(
        encodeShareTemplate(template),
        newId: 'imported',
      );
      expect(restored.body, template.body);
      expect(restored.id, 'imported');
      expect(
        decodeSharedParameters(encodeSharedParameters({BrewParameter.notes})),
        {BrewParameter.notes},
      );
      expect(
        defaultSharedParameters.intersection({
          BrewParameter.farm,
          BrewParameter.producer,
          BrewParameter.cost,
        }),
        isEmpty,
      );
    },
  );
  test(
    'unknown cost differs from a free coffee and archived lots count',
    () async {
      final lots = await repo.watchLots().first;
      final archived = lots.single.copyWith(archivedAtMs: const Value(123));
      double? costFor(Coffee value) =>
          brewCost(brew, pricePerKgByCoffee([value], [archived]));
      expect(costFor(coffee), 0.9);
      final unknown = coffee.copyWith(
        paidPriceCents: const Value(null),
        roastLevel: const Value(null),
        flavorProfile: const Value(null),
      );
      final values = shareTemplateValues(
        strings: AppLocalizationsEn(),
        coffee: unknown,
        brew: brew,
        components: [],
        cost: costFor(unknown),
      );
      expect(
        TemplateEngine.render(
          '<cost> <farm> <producer> <altitude> <harvest> <roast_level> <flavor_notes>',
          values,
        ),
        '— — — — — — —',
      );
      final free = coffee.copyWith(paidPriceCents: const Value(0));
      expect(
        shareTemplateValues(
          strings: AppLocalizationsEn(),
          coffee: free,
          brew: brew,
          components: [],
          cost: costFor(free),
        )['cost'],
        '€0.00',
      );
    },
  );
}
