import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class CafeShareRow {
  const CafeShareRow(this.id, this.label, this.value, {this.personal = false});

  final String id;
  final String label;
  final String value;
  final bool personal;
}

List<CafeShareRow> cafeShareRows(
  BuildContext context,
  Cafe cafe,
  CafeDrink drink,
  String? roaster,
) {
  final s = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final rows = <CafeShareRow>[];
  void add(String id, String label, String? value, {bool personal = false}) {
    if (value == null || value.trim().isEmpty) return;
    rows.add(CafeShareRow(id, label, value.trim(), personal: personal));
  }

  add('cafe', s.cafeVenue, cafe.name);
  add('city', s.cafeCity, cafe.city);
  add('country', s.cafeVenueCountry, cafe.country);
  add('drink', s.cafeDrinkType, drink.drinkType);
  add('roaster', s.roaster, roaster);
  add('coffee', s.beanName, drink.coffeeName);
  add('origin', s.cafeOriginCountry, drink.originCountry);
  add('process', s.process, drink.process);
  add('variety', s.variety, drink.variety);
  add(
    'date',
    s.date,
    formatRegionalDate(
      DateTime.fromMillisecondsSinceEpoch(drink.drankAtMs),
      regionalLocale,
    ),
    personal: true,
  );
  add(
    'rating',
    s.rating,
    drink.rating == null
        ? null
        : formatDecimal(drink.rating, pattern: '0.#', locale: locale),
    personal: true,
  );
  add(
    'price',
    s.cafePrice,
    drink.priceCents == null
        ? null
        : formatCafeCurrency(drink.priceCents! / 100, drink.currency, locale),
    personal: true,
  );
  add('notes', s.notes, drink.notes, personal: true);
  return rows;
}

String cafeShareText(List<CafeShareRow> rows, Set<String> selected) => rows
    .where((row) => selected.contains(row.id))
    .map((row) => '${row.label}: ${row.value}')
    .join('\n');
