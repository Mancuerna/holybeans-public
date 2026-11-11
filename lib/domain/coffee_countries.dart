import 'package:holybeans/domain/text_folding.dart';

/// Coffee-producing countries with their ISO 3166-1 alpha-2 code, so a
/// free-text origin like "Etiopía" or "ethiopia" can show a flag.
class CoffeeCountry {
  const CoffeeCountry(this.code, this.english, this.spanish, [this.aliases]);

  final String code;
  final String english;
  final String spanish;
  final List<String>? aliases;

  String nameFor(String languageCode) =>
      languageCode == 'es' ? spanish : english;

  /// Regional indicator pair, e.g. KE → 🇰🇪. Brazil gets a skull instead:
  /// an easter egg the user asked for, with a sound when it is picked.
  String get flag => code == 'BR'
      ? '💀'
      : String.fromCharCodes(
          code.codeUnits.map((unit) => 0x1F1E6 + unit - 0x41),
        );
}

const coffeeCountries = <CoffeeCountry>[
  CoffeeCountry('BO', 'Bolivia', 'Bolivia'),
  CoffeeCountry('BR', 'Brazil', 'Brasil'),
  CoffeeCountry('BI', 'Burundi', 'Burundi'),
  CoffeeCountry('CM', 'Cameroon', 'Camerún'),
  CoffeeCountry('CN', 'China', 'China', ['yunnan']),
  CoffeeCountry('CO', 'Colombia', 'Colombia'),
  CoffeeCountry('CD', 'DR Congo', 'RD del Congo', [
    'congo',
    'democratic republic of the congo',
    'republica democratica del congo',
    'drc',
  ]),
  CoffeeCountry('CR', 'Costa Rica', 'Costa Rica'),
  CoffeeCountry('CU', 'Cuba', 'Cuba'),
  CoffeeCountry('DO', 'Dominican Republic', 'República Dominicana'),
  CoffeeCountry('EC', 'Ecuador', 'Ecuador'),
  CoffeeCountry('SV', 'El Salvador', 'El Salvador', ['salvador']),
  CoffeeCountry('ET', 'Ethiopia', 'Etiopía'),
  CoffeeCountry('GT', 'Guatemala', 'Guatemala'),
  CoffeeCountry('HT', 'Haiti', 'Haití'),
  CoffeeCountry('HN', 'Honduras', 'Honduras'),
  CoffeeCountry('IN', 'India', 'India'),
  CoffeeCountry('ID', 'Indonesia', 'Indonesia', [
    'sumatra',
    'java',
    'sulawesi',
    'bali',
    'flores',
  ]),
  CoffeeCountry('JM', 'Jamaica', 'Jamaica'),
  CoffeeCountry('KE', 'Kenya', 'Kenia'),
  CoffeeCountry('LA', 'Laos', 'Laos'),
  CoffeeCountry('MW', 'Malawi', 'Malaui', ['malawi']),
  CoffeeCountry('MX', 'Mexico', 'México'),
  CoffeeCountry('MM', 'Myanmar', 'Myanmar', ['birmania', 'burma']),
  CoffeeCountry('NP', 'Nepal', 'Nepal'),
  CoffeeCountry('NI', 'Nicaragua', 'Nicaragua'),
  CoffeeCountry('PA', 'Panama', 'Panamá'),
  CoffeeCountry('PG', 'Papua New Guinea', 'Papúa Nueva Guinea', ['png']),
  CoffeeCountry('PE', 'Peru', 'Perú'),
  CoffeeCountry('PH', 'Philippines', 'Filipinas'),
  CoffeeCountry('PR', 'Puerto Rico', 'Puerto Rico'),
  CoffeeCountry('RW', 'Rwanda', 'Ruanda', ['rwanda']),
  CoffeeCountry('ES', 'Spain', 'España'),
  CoffeeCountry('TW', 'Taiwan', 'Taiwán'),
  CoffeeCountry('TZ', 'Tanzania', 'Tanzania'),
  CoffeeCountry('TH', 'Thailand', 'Tailandia'),
  CoffeeCountry('TL', 'Timor-Leste', 'Timor Oriental', ['east timor', 'timor']),
  CoffeeCountry('UG', 'Uganda', 'Uganda'),
  CoffeeCountry('US', 'Hawaii', 'Hawái', ['hawaii', 'kona', 'usa']),
  CoffeeCountry('VE', 'Venezuela', 'Venezuela'),
  CoffeeCountry('VN', 'Vietnam', 'Vietnam', ['viet nam']),
  CoffeeCountry('YE', 'Yemen', 'Yemen'),
  CoffeeCountry('ZM', 'Zambia', 'Zambia'),
  CoffeeCountry('ZW', 'Zimbabwe', 'Zimbabue', ['zimbabwe']),
];

/// Lowercase, accent-free form used to compare country names.
String foldCountryName(String text) {
  final buffer = StringBuffer();
  for (final unit in text.trim().toLowerCase().codeUnits) {
    buffer.writeCharCode(foldLatinAccent(unit));
  }
  return buffer.toString().replaceAll(RegExp(r'[\s\-.]+'), ' ');
}

final Map<String, CoffeeCountry> _byName = {
  for (final country in coffeeCountries)
    for (final name in [
      country.english,
      country.spanish,
      country.code,
      ...?country.aliases,
    ])
      foldCountryName(name): country,
};

/// The country a free-text origin names, or null if it isn't recognised.
CoffeeCountry? coffeeCountryFor(String? text) {
  if (text == null) return null;
  return _byName[foldCountryName(text)];
}
