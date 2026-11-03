import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

Map<String, String> coffeeLabelValues({
  required Coffee coffee,
  required List<CoffeeComponent> components,
  CoffeeLot? lot,
  FrozenPortion? portion,
}) {
  if (lot != null && lot.coffeeId != coffee.id ||
      portion != null && (lot == null || portion.lotId != lot.id)) {
    throw ArgumentError('Label sources do not belong together');
  }
  final locale = regionalLocale.toString();
  String date(String? iso) {
    final value = iso == null ? null : DateTime.tryParse(iso);
    return value == null ? '' : DateFormat.yMd(locale).format(value);
  }

  String parts(String? Function(CoffeeComponent) pick) => {
    for (final part in components)
      if (part.coffeeId == coffee.id &&
          (pick(part)?.trim().isNotEmpty ?? false))
        pick(part)!.trim(),
  }.join(', ');
  return {
    'coffee': coffee.name,
    'roaster': coffee.roaster,
    'country': parts((c) => c.country),
    'region': parts((c) => c.region),
    'farm': parts((c) => c.farm),
    'producer': parts((c) => c.producer),
    'variety': parts((c) => c.variety),
    'process': parts((c) => c.process),
    'flavor_notes': coffee.flavorProfile ?? '',
    'roast_date': date(lot?.roastDate),
    'freeze_date': date(portion?.frozenDate),
    // A portion's label describes the amount originally packaged, even when
    // some of it has subsequently been consumed.
    'portion_weight': portion == null
        ? ''
        : formatGrams(portion.initialGrams, locale),
    'portion_label': portion?.label ?? '',
  };
}

Map<String, String> labelTagNames(AppLocalizations s, LabelKind kind) => {
  'coffee': s.beanName,
  'roaster': s.roaster,
  'country': s.country,
  'region': s.region,
  'variety': s.variety,
  'process': s.process,
  'farm': s.farm,
  'producer': s.producer,
  'flavor_notes': s.flavorProfile,
  'roast_date': s.labelRoastDate,
  if (kind == LabelKind.frozen) ...{
    'freeze_date': s.labelFreezeDate,
    'portion_weight': s.labelPortionWeight,
    'portion_label': s.labelPortionCode,
  },
};
