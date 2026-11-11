import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class BeanShareRow {
  const BeanShareRow(this.id, this.label, this.value, {this.personal = false});
  final String id;
  final String label;
  final String value;
  final bool personal;
}

List<BeanShareRow> beanShareRows(
  AppLocalizations s,
  Coffee coffee,
  List<CoffeeComponent> components,
  CoffeeStock stock,
) {
  final rows = <BeanShareRow>[];
  void add(String id, String label, String? value, {bool personal = false}) {
    if (value == null || value.trim().isEmpty) return;
    rows.add(BeanShareRow(id, label, value.trim(), personal: personal));
  }

  add('name', s.beanName, coffee.name);
  add('roaster', s.roaster, coffee.roaster);
  for (final (index, part) in components.indexed) {
    void component(String id, String label, String? value) =>
        add('$index-$id', label, value);
    component('country', s.country, part.country);
    component('region', s.region, part.region);
    component('farm', s.farm, part.farm);
    component('producer', s.producer, part.producer);
    component('variety', s.variety, part.variety);
    component('process', s.process, part.process);
    component(
      'altitude',
      s.altitudeHeading,
      altitudeLabel(part.altitudeMeters, part.altitudeMaxMeters),
    );
    component('harvest', s.harvest, part.harvest);
  }
  add(
    'roast',
    s.roastLevel,
    coffee.roastLevel == null ? null : roastLevelLabel(s, coffee.roastLevel!),
  );
  add('flavor', s.flavorProfile, coffee.flavorProfile);
  final locale = regionalLocale.toString();
  add(
    'price',
    beanDetailLabel(s.paidPrice),
    coffee.paidPriceCents == null
        ? null
        : formatEuro(coffee.paidPriceCents! / 100, locale),
    personal: true,
  );
  add(
    'rating',
    s.rating,
    coffee.rating == null
        ? null
        : NumberFormat('0.#', locale).format(coffee.rating),
    personal: true,
  );
  add('notes', s.notes, coffee.notes, personal: true);
  add(
    'remaining',
    s.stockAdjustFresh,
    stock.remainingGrams == null
        ? null
        : formatGrams(stock.remainingGrams!, locale),
    personal: true,
  );
  if (stock.frozenGrams > 0) {
    add(
      'frozen',
      s.frozen,
      formatGrams(stock.frozenGrams, locale),
      personal: true,
    );
  }
  return rows;
}

String beanShareText(List<BeanShareRow> rows, Set<String> selected) => rows
    .where((row) => selected.contains(row.id))
    .map((row) => '${row.label}: ${row.value}')
    .join('\n');
