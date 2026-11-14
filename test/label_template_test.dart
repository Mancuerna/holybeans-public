import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/ui/labels/label_values.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';

const label = LabelTemplate(
  id: 'label',
  name: 'Bag',
  kind: LabelKind.coffee,
  body: '**<coffee>**\n<roaster>\n<roast_date>',
);
const brew = ShareTemplate(
  id: 'brew',
  name: 'Recipe',
  style: ShareTemplateStyle.espresso,
  body: '<coffee> <dose>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDateFormatting);
  test(
    'label catalogue uses the same engine without exposing brew-only fields',
    () {
      expect(
        label.render({'coffee': '<roaster> **literal**', 'roaster': 'Roaster'}),
        '**<roaster\\> \\*\\*literal\\*\\***\nRoaster\n—',
      );
      expect(TemplateEngine.unknownTags('<roast_date>'), {'roast_date'});
      expect(
        TemplateEngine.unknownTags(
          '<roast_date>',
          allowedTags: coffeeLabelTags,
        ),
        isEmpty,
      );
      expect(
        () => const LabelTemplate(
          id: 'bad',
          name: 'Bad',
          kind: LabelKind.coffee,
          body: '<dose>',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const LabelTemplate(
          id: 'bad',
          name: 'Bad',
          kind: LabelKind.coffee,
          body: '<freeze_date>',
        ).validate(),
        throwsFormatException,
      );
    },
  );

  test(
    'old preferences load and every brew setting operation preserves labels',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      expect(ShareConfiguration.decode('["notes"]').labelTemplates, isEmpty);
      final previous = ShareConfiguration(fields: {BrewParameter.notes})
          .toJson();
      expect(previous.containsKey('labelTemplates'), isFalse);
      expect(
        ShareConfiguration.decode(jsonEncode(previous)).labelDefaults,
        isEmpty,
      );
      expect(
        ShareConfiguration.decode(jsonEncode(previous)).labelTemplates,
        isEmpty,
      );
      await settings.saveLabelTemplate(label);
      await settings.selectLabel(LabelKind.coffee, label.id);
      await settings.saveTemplate(brew);
      await settings.select(ShareTemplateStyle.espresso, brew.id);
      await BrewParameterSettings(db).saveShared({BrewParameter.time});
      await settings.deleteTemplate(brew.id);
      await settings.saveOverlayBackgroundOpacity(0.7);
      expect(
        (await settings.load()).selectedLabel(LabelKind.coffee)?.id,
        label.id,
      );
      expect((await settings.load()).labelTemplates.single.body, label.body);
      await settings.saveTemplate(brew);
      await settings.select(ShareTemplateStyle.espresso, brew.id);
      await settings.deleteLabelTemplate(label.id);
      final remaining = await settings.load();
      expect(remaining.templates.single.body, brew.body);
      expect(remaining.selected(ShareTemplateStyle.espresso)?.id, brew.id);
      expect(remaining.fields, {BrewParameter.time});
    },
  );

  test(
    'label templates survive backup restore alongside existing brew templates',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      await Future.wait([
        settings.saveTemplate(brew),
        settings.saveLabelTemplate(
          LabelTemplate(
            id: label.id,
            name: label.name,
            kind: label.kind,
            body: label.body,
            imageOptions: const LabelImageOptions(
              position: LabelImagePosition.right,
              alignment: LabelImageAlignment.end,
              size: 0.3,
              mode: LabelImageMode.photo,
              contrast: 1.5,
              offsetX: -0.35,
              offsetY: 0.6,
            ),
            imagePng: LabelGraphic.prepare(
              img.encodePng(img.Image(width: 4, height: 4)),
            ),
          ),
        ),
      ]);
      await settings.select(ShareTemplateStyle.espresso, brew.id);
      await settings.selectLabel(LabelKind.coffee, label.id);
      final before = (await settings.load()).toJson();
      final backup = await JournalBackup(db).exportJson();
      await settings.deleteLabelTemplate(label.id);
      await settings.deleteTemplate(brew.id);
      await JournalBackup(db).restoreJson(backup);
      expect((await settings.load()).toJson(), before);
    },
  );

  test(
    'defaults are independent by label kind and validate their target',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      const frozen = LabelTemplate(
        id: 'frozen',
        name: 'Portion',
        kind: LabelKind.frozen,
        body: '<coffee> <portion_weight>',
      );
      await settings.saveLabelTemplate(label);
      await settings.saveLabelTemplate(frozen);
      await Future.wait([
        settings.selectLabel(LabelKind.coffee, label.id),
        settings.selectLabel(LabelKind.frozen, frozen.id),
      ]);
      var configuration = await settings.load();
      expect(configuration.selectedLabel(LabelKind.coffee)?.id, label.id);
      expect(configuration.selectedLabel(LabelKind.frozen)?.id, frozen.id);
      await expectLater(
        settings.selectLabel(LabelKind.coffee, frozen.id),
        throwsArgumentError,
      );
      await expectLater(
        settings.selectLabel(LabelKind.coffee, 'missing'),
        throwsArgumentError,
      );
      await settings.selectLabel(LabelKind.coffee, null);
      configuration = await settings.load();
      expect(configuration.selectedLabel(LabelKind.coffee), isNull);
      expect(configuration.selectedLabel(LabelKind.frozen)?.id, frozen.id);
      await settings.deleteLabelTemplate(frozen.id);
      expect((await settings.load()).labelDefaults, isEmpty);
    },
  );

  test(
    'editing a default preserves it and changing its kind clears it',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final settings = ShareTemplateSettings(db);
      await settings.saveLabelTemplate(label);
      await settings.selectLabel(LabelKind.coffee, label.id);
      await settings.saveLabelTemplate(
        LabelTemplate(
          id: label.id,
          name: 'Renamed',
          kind: LabelKind.coffee,
          body: '<roaster>',
        ),
      );
      expect(
        (await settings.load()).selectedLabel(LabelKind.coffee)?.body,
        '<roaster>',
      );
      await settings.saveLabelTemplate(
        LabelTemplate(
          id: label.id,
          name: 'Frozen',
          kind: LabelKind.frozen,
          body: '<freeze_date>',
        ),
      );
      expect((await settings.load()).labelDefaults, isEmpty);
    },
  );

  test(
    'missing or mismatched default IDs fall back without losing templates',
    () {
      final configuration = ShareConfiguration.decode(
        jsonEncode(
          ShareConfiguration(
            fields: {BrewParameter.notes},
            labelTemplates: [label],
            labelDefaults: {
              LabelKind.coffee: 'missing',
              LabelKind.frozen: label.id,
            },
          ).toJson(),
        ),
      );
      expect(configuration.selectedLabel(LabelKind.coffee), isNull);
      expect(configuration.selectedLabel(LabelKind.frozen), isNull);
      expect(configuration.labelTemplates.single.id, label.id);
    },
  );

  test(
    'dates and weight come from the chosen lot and original frozen portion',
    () {
      const coffee = Coffee(
        id: 'coffee',
        name: 'Coffee',
        roaster: 'Roaster',
        isFavorite: false,
        isDecaf: false,
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      const lot = CoffeeLot(
        id: 'lot',
        coffeeId: 'coffee',
        roastDate: '2026-10-20',
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      const portion = FrozenPortion(
        id: 'frozen',
        lotId: 'lot',
        label: 'F123',
        frozenDate: '2026-10-25',
        initialGrams: 18,
        remainingGrams: 5,
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      final values = coffeeLabelValues(
        coffee: coffee,
        components: [],
        lot: lot,
        portion: portion,
      );
      expect(values['roast_date'], contains('20'));
      expect(values['freeze_date'], contains('25'));
      expect(values['portion_weight'], '18 g');
      expect(values['portion_label'], 'F123');
      expect(
        coffeeLabelValues(coffee: coffee, components: [])['roast_date'],
        '',
      );
      expect(
        () =>
            coffeeLabelValues(coffee: coffee, components: [], portion: portion),
        throwsArgumentError,
      );
    },
  );
}
