import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:holybeans/ui/labels/label_values.dart';
import 'package:intl/date_symbol_data_local.dart';

const _coffee = Coffee(
  id: 'coffee',
  name: 'Coffee',
  roaster: 'Roaster',
  isFavorite: false,
  isDecaf: false,
  createdAtMs: 0,
  updatedAtMs: 0,
);
const _lot = CoffeeLot(
  id: 'lot',
  coffeeId: 'coffee',
  roastDate: '2024-02-28',
  openedDate: '2024-02-28',
  archivedAtMs: 1,
  createdAtMs: 0,
  updatedAtMs: 0,
);
final _brew = Brew(
  recipientIsPortafilter: false,
  id: 'brew',
  coffeeId: 'coffee',
  lotId: 'lot',
  methodName: 'V60',
  isPreGround: false,
  isFavorite: false,
  brewedAtMs: DateTime(2024, 3, 1, 0, 1).millisecondsSinceEpoch,
  createdAtMs: 0,
  updatedAtMs: 0,
);
const _tag = '<days_from_roast>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDateFormatting);

  for (final s in [AppLocalizationsEs(), AppLocalizationsEn()]) {
    test(
      'historical brew uses its archived lot and calendar days (${s.localeName})',
      () {
        final values = shareTemplateValues(
          strings: s,
          coffee: _coffee,
          brew: _brew,
          lot: _lot,
          components: [],
        );
        expect(TemplateEngine.render(_tag, values), '2');
        expect(TemplateEngine.missingTags(_tag, values), isEmpty);
        expect(
          shareTemplateValues(
            strings: s,
            coffee: _coffee,
            brew: _brew.copyWith(
              brewedAtMs: DateTime(2024, 2, 28, 23, 59).millisecondsSinceEpoch,
            ),
            lot: _lot,
            components: [],
          )['days_from_roast'],
          '0',
        );
      },
    );
  }

  test('missing, invalid, future or unrelated roast dates stay unknown', () {
    for (final lot in <CoffeeLot?>[
      null,
      _lot.copyWith(roastDate: const Value(null)),
      _lot.copyWith(roastDate: const Value('invalid')),
      _lot.copyWith(roastDate: const Value('2024-03-02')),
      _lot.copyWith(id: 'another-lot'),
      _lot.copyWith(coffeeId: 'another-coffee'),
    ]) {
      final values = shareTemplateValues(
        strings: AppLocalizationsEn(),
        coffee: _coffee,
        brew: _brew,
        lot: lot,
        components: [],
      );
      expect(TemplateEngine.render(_tag, values), '—');
      expect(TemplateEngine.missingTags(_tag, values), {'days_from_roast'});
    }
    expect(
      shareTemplateValues(
        strings: AppLocalizationsEn(),
        coffee: _coffee,
        brew: _brew.copyWith(lotId: const Value(null)),
        lot: _lot,
        components: [],
      )['days_from_roast'],
      '',
    );
  });

  test('every brew style accepts, exports and previews the tag', () {
    for (final style in ShareTemplateStyle.values) {
      final template = ShareTemplate(
        id: 'template',
        name: 'Roast age',
        style: style,
        body: 'Rest: $_tag days',
      );
      template.validate();
      expect(
        decodeShareTemplate(encodeShareTemplate(template), newId: 'copy').body,
        template.body,
      );
      expect(
        TemplateEngine.render(
          template.body,
          sampleShareTemplateValues(AppLocalizationsEn(), style),
        ),
        'Rest: 14 days',
      );
    }
  });

  for (final kind in LabelKind.values) {
    test('${kind.name} label counts to print date, including frozen time', () {
      final template = LabelTemplate(
        id: 'label',
        name: 'Roast age',
        kind: kind,
        body: _tag,
      );
      template.validate();
      expect(LabelTemplate.fromJson(template.toJson()).body, _tag);
      final values = coffeeLabelValues(
        coffee: _coffee,
        components: [],
        lot: _lot,
        now: DateTime(2024, 3, 10, 0, 1),
        portion: kind == LabelKind.coffee
            ? null
            : const FrozenPortion(
                id: 'portion',
                label: 'F001',
                lotId: 'lot',
                frozenDate: '2024-02-29',
                initialGrams: 18,
                remainingGrams: 18,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
      );
      expect(template.render(values), '11');
      expect(
        labelTagNames(AppLocalizationsEs(), kind)['days_from_roast'],
        'Días desde el tueste',
      );
      expect(
        labelTagNames(AppLocalizationsEn(), kind)['days_from_roast'],
        'Days from roast',
      );
    });
  }

  test('labels distinguish roast day from missing or future dates', () {
    for (final (lot, expected) in <(CoffeeLot?, String)>[
      (_lot, '0'),
      (null, '—'),
      (_lot.copyWith(roastDate: const Value(null)), '—'),
      (_lot.copyWith(roastDate: const Value('invalid')), '—'),
      (_lot.copyWith(roastDate: const Value('2024-02-29')), '—'),
    ]) {
      final values = coffeeLabelValues(
        coffee: _coffee,
        components: [],
        lot: lot,
        now: DateTime(2024, 2, 28, 23, 59),
      );
      expect(
        TemplateEngine.render(_tag, values, allowedTags: coffeeLabelTags),
        expected,
      );
    }
  });
}
