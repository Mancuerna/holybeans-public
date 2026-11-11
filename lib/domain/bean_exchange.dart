import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/https_link.dart';

typedef SharedCoffee = ({
  String name,
  String roaster,
  String? roastLevel,
  bool isDecaf,
  String? flavorProfile,
  String? shopUrl,
  int? paidPriceCents,
});
typedef SharedComponent = ({int position, SharedOrigin origin});
typedef SharedLot = ({double? initialGrams, int createdAtMs});
typedef ExistingCoffee = ({String id, String name, String roaster});

/// Coffee cards passed between people and apps: a `.holybeans` file, a QR
/// code or text an AI filled in. A card describes the coffee and one bag of
/// it (weight, price, roast date), never the sender's notes, rating, stock
/// or brews.
///
/// Reading is lenient, since AI answers vary: a list or a single coffee,
/// with or without the header, inside a code block, numbers as text, flat
/// origin fields. Whatever cannot be read is dropped and named, never
/// guessed.

/// The file extension, and the MIME type HolyBeans shares it with.
const beanFileExtension = 'holybeans';
const beanFileMimeType = 'application/x-holybeans';

/// How a QR code's text starts: a link HolyBeans opens.
const beanQrPrefix = 'holybeans://bean?d=';
const beanQrMaxBytes = 8 * 1024;
const beanQrMaxDecodedBytes = 256 * 1024;

const beanFormat = 'holybeans-beans';
const beanFormatVersion = 1;

/// Roast levels as stored, from darkest to lightest.
const beanRoastLevels = ['dark', 'medium', 'omni', 'light', 'ultra_light'];

/// One origin of a coffee: a single origin has one, a blend several.
class SharedOrigin {
  const SharedOrigin({
    this.country,
    this.region,
    this.farm,
    this.producer,
    this.variety,
    this.process,
    this.altitudeMeters,
    this.altitudeMaxMeters,
    this.harvest,
  });

  final String? country;
  final String? region;
  final String? farm;
  final String? producer;
  final String? variety;
  final String? process;
  final int? altitudeMeters;
  final int? altitudeMaxMeters;
  final String? harvest;

  bool get isEmpty =>
      [
        country,
        region,
        farm,
        producer,
        variety,
        process,
        harvest,
      ].every((value) => value == null) &&
      altitudeMeters == null &&
      altitudeMaxMeters == null;

  Map<String, Object> toJson() => {
    'country': ?country,
    'region': ?region,
    'farm': ?farm,
    'producer': ?producer,
    'variety': ?variety,
    'process': ?process,
    'altitudeMeters': ?altitudeMeters,
    'altitudeMaxMeters': ?altitudeMaxMeters,
    'harvest': ?harvest,
  };
}

/// A coffee as a card: what it is and one bag of it.
class SharedBean {
  const SharedBean({
    required this.name,
    required this.roaster,
    this.roastLevel,
    this.decaf = false,
    this.flavorNotes = const [],
    this.shopUrl,
    this.priceCents,
    this.bagGrams,
    this.roastDate,
    this.origins = const [],
  });

  /// The card of [coffee]: its origins, and the price and weight of its
  /// latest bag. The roast date stays out: the receiver's bag has its own.
  factory SharedBean.fromFacts(
    SharedCoffee coffee,
    List<SharedComponent> components,
    List<SharedLot> lots,
  ) {
    final weighed = [
      for (final lot in lots)
        if (lot.initialGrams case final grams? when grams > 0) (lot, grams),
    ]..sort((a, b) => b.$1.createdAtMs.compareTo(a.$1.createdAtMs));
    final totalGrams = weighed.fold<double>(0, (sum, bag) => sum + bag.$2);
    final bagGrams = weighed.isEmpty ? null : weighed.first.$2;
    // The price covers every bag bought; the card carries the latest one's
    // share of it.
    final priceCents = switch ((coffee.paidPriceCents, bagGrams)) {
      (final cents?, final grams?) when totalGrams > 0 =>
        (cents * grams / totalGrams).round(),
      (final cents?, null) => cents,
      _ => null,
    };
    final sorted = [...components]
      ..sort((a, b) => a.position.compareTo(b.position));
    return SharedBean(
      name: coffee.name,
      roaster: coffee.roaster,
      roastLevel: coffee.roastLevel,
      decaf: coffee.isDecaf,
      flavorNotes: _notesFrom(coffee.flavorProfile),
      shopUrl: coffee.shopUrl,
      priceCents: priceCents,
      bagGrams: bagGrams,
      origins: [
        for (final component in sorted)
          if (!component.origin.isEmpty) component.origin,
      ],
    );
  }

  final String name;

  /// May be empty when the card did not say; the form asks for it.
  final String roaster;
  final String? roastLevel;
  final bool decaf;
  final List<String> flavorNotes;
  final String? shopUrl;

  /// What the bag cost, in euro cents.
  final int? priceCents;
  final double? bagGrams;

  /// ISO calendar date, `yyyy-MM-dd`.
  final String? roastDate;
  final List<SharedOrigin> origins;

  /// The notes as the coffee form keeps them, comma separated.
  String? get flavorProfile =>
      flavorNotes.isEmpty ? null : flavorNotes.join(', ');

  Map<String, Object> toJson() => {
    'name': name,
    'roaster': roaster,
    'roastLevel': ?roastLevel,
    if (decaf) 'decaf': true,
    if (flavorNotes.isNotEmpty) 'flavorNotes': flavorNotes,
    'shopUrl': ?shopUrl,
    if (priceCents case final cents?) 'price': cents / 100,
    'bagGrams': ?bagGrams,
    'roastDate': ?roastDate,
    if (origins.isNotEmpty)
      'origins': [for (final origin in origins) origin.toJson()],
  };
}

/// A coffee read from a card, with the fields that could not be read.
class ReadBean {
  const ReadBean(this.bean, {this.dropped = const []});

  final SharedBean bean;

  /// Field names left out because their value made no sense.
  final List<String> dropped;
}

/// Why nothing could be read.
enum BeanReadError {
  /// Not valid coffee JSON, nor valid coffee JSON inside the text.
  notJson,

  /// JSON without any coffee in it.
  noBeans,

  /// A card from a newer HolyBeans.
  newerVersion,
  tooLarge,
}

class BeanReadException implements Exception {
  const BeanReadException(this.error, {this.detail});

  final BeanReadError error;

  /// Where the JSON reader stopped, for the device log.
  final String? detail;

  @override
  String toString() =>
      'BeanReadException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// The file contents for [beans]: indented JSON with the format header.
String encodeBeans(List<SharedBean> beans) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': beanFormat,
      'version': beanFormatVersion,
      'beans': [for (final bean in beans) bean.toJson()],
    });

/// The QR text for [bean]: a link carrying its card, compressed.
String beanQrText(SharedBean bean) {
  final json = utf8.encode(
    jsonEncode({
      'format': beanFormat,
      'version': beanFormatVersion,
      'beans': [bean.toJson()],
    }),
  );
  final packed = const GZipEncoder().encodeBytes(json);
  return '$beanQrPrefix${base64Url.encode(packed).replaceAll('=', '')}';
}

/// Reads coffees from a file, a QR code's text or an AI's answer. Coffees
/// without a name are skipped. Throws [BeanReadException] when there is
/// nothing to read.
List<ReadBean> readBeans(String text) {
  final source = text.trim();
  final Object? decoded;
  if (source.startsWith(beanQrPrefix)) {
    if (source.length > beanQrMaxBytes ||
        utf8.encode(source).length > beanQrMaxBytes) {
      throw const BeanReadException(BeanReadError.tooLarge);
    }
    decoded = _decodeQr(source.substring(beanQrPrefix.length));
  } else {
    decoded = _decodeJson(source);
  }
  if (decoded is Map &&
      decoded.containsKey('version') &&
      decoded['version'] is! int) {
    throw const BeanReadException(
      BeanReadError.notJson,
      detail: 'Invalid format version',
    );
  }
  final List<Object?> items;
  switch (decoded) {
    case {'version': final int version} when version > beanFormatVersion:
      throw const BeanReadException(BeanReadError.newerVersion);
    case {'beans': final List<Object?> beans}:
      items = beans;
    case final List<Object?> beans:
      items = beans;
    case final Map<String, Object?> bean when bean.containsKey('name'):
      items = [bean];
    default:
      throw const BeanReadException(BeanReadError.noBeans);
  }
  final read = [
    for (final item in items)
      if (item case final Map<String, Object?> map) ?_readBean(map),
  ];
  if (read.isEmpty) throw const BeanReadException(BeanReadError.noBeans);
  return read;
}

Object? _decodeQr(String data) {
  try {
    final padded = data.padRight((data.length + 3) ~/ 4 * 4, '=');
    final output = _BoundedQrOutput();
    // The native decoder buffers all chunks before writing to OutputStream.
    // The Dart decoder writes as it inflates, so the cap stops expansion early.
    final valid = const GZipDecoderWeb().decodeStream(
      InputMemoryStream(base64Url.decode(padded)),
      output,
      verify: true,
    );
    if (output.limitExceeded) {
      throw const BeanReadException(BeanReadError.tooLarge);
    }
    if (!valid) throw const FormatException('Invalid compressed coffee card');
    return jsonDecode(utf8.decode(output.getBytes()));
  } on BeanReadException {
    rethrow;
  } on Object {
    throw const BeanReadException(BeanReadError.notJson);
  }
}

class _BoundedQrOutput extends OutputMemoryStream {
  bool limitExceeded = false;
  void _reserve(int count) {
    if (length + count > beanQrMaxDecodedBytes) {
      limitExceeded = true;
      throw const BeanReadException(BeanReadError.tooLarge);
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _reserve(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _reserve(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _reserve(count);
    super.writeBackReference(distance, count);
  }
}

/// The JSON in [text], which may be wrapped in prose or a code block, or
/// have picked up stray characters on the way: copying from chats, web
/// pages or a synced computer clipboard can turn line breaks into
/// vertical tabs, spaces into no-break spaces, add invisible characters or
/// curl the quotes. Each repair is
/// tried only when the text as it came does not read.
Object? _decodeJson(String text) {
  FormatException? last;
  for (final candidate in [
    text,
    _unescapeMarkdown(text),
    _plainSpaces(text),
    _straightQuotes(_plainSpaces(text)),
    _unescapeMarkdown(_straightQuotes(_plainSpaces(text))),
  ]) {
    try {
      return _decodeWrapped(candidate);
    } on FormatException catch (error) {
      last = error;
    }
  }
  throw BeanReadException(
    BeanReadError.notJson,
    detail: last == null ? null : _describe(last),
  );
}

/// [text] as JSON, or the JSON object or list inside it.
Object? _decodeWrapped(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    final starts = [text.indexOf('{'), text.indexOf('[')]
      ..removeWhere((index) => index < 0);
    if (starts.isEmpty) {
      throw const FormatException('No JSON object or list');
    }
    final start = starts.reduce((a, b) => a < b ? a : b);
    final end = text[start] == '{'
        ? text.lastIndexOf('}')
        : text.lastIndexOf(']');
    if (end <= start) throw const FormatException('Unclosed JSON');
    return jsonDecode(text.substring(start, end + 1));
  }
}

String _plainSpaces(String text) => text
    // Line breaks some programs and synced clipboards use, such as the
    // vertical tab for soft breaks, become plain ones.
    .replaceAll(RegExp('[\u000B\u000C\u0085\u2028\u2029]'), '\n')
    .replaceAll(RegExp('[\u00A0\u2000-\u200A\u202F\u205F\u3000]'), ' ')
    .replaceAll(RegExp('[\u200B-\u200D\u2060\uFEFF]'), '');

String _straightQuotes(String text) =>
    text.replaceAll(RegExp('[\u201C\u201D\u201E\u201F\u2033]'), '"');

/// Chat renderers may copy Markdown escapes into JSON, including its arrays.
/// Only invalid ASCII punctuation escapes are repaired after decoding fails.
/// Consume other escape pairs intact so a literal backslash stays literal.
String _unescapeMarkdown(String text) {
  final result = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == r'\' && i + 1 < text.length) {
      final next = text[++i];
      final code = next.codeUnitAt(0);
      final punctuation =
          (code >= 33 && code <= 47) ||
          (code >= 58 && code <= 64) ||
          (code >= 91 && code <= 96) ||
          (code >= 123 && code <= 126);
      // Quotes, backslashes and slashes are valid JSON escapes.
      if (!punctuation || next == '"' || next == r'\' || next == '/') {
        result.write(char);
      }
      result.write(next);
    } else {
      result.write(char);
    }
  }
  return result.toString();
}

/// The reader's complaint and the character it stopped at, as a code
/// point, without copying the person's text into the log.
String _describe(FormatException error) {
  final offset = error.offset;
  final source = error.source;
  final at = offset != null && source is String && offset < source.length
      ? ' at $offset (U+${source.codeUnitAt(offset).toRadixString(16).toUpperCase().padLeft(4, '0')})'
      : '';
  return '${error.message}$at';
}

ReadBean? _readBean(Map<String, Object?> json) {
  final dropped = <String>[];
  String? text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    final num number => number.toString(),
    _ => null,
  };
  String? field(String key) {
    final value = json[key];
    final read = text(value);
    if (value != null && read == null && value is! String) dropped.add(key);
    return read;
  }

  final name = field('name');
  if (name == null) return null;

  String? roastLevel;
  if (field('roastLevel') case final level?) {
    final code = level.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (beanRoastLevels.contains(code)) {
      roastLevel = code;
    } else {
      dropped.add('roastLevel');
    }
  }

  final decaf = switch (json['decaf']) {
    final bool flag => flag,
    final String word => const [
      'true',
      'yes',
      'sí',
      'si',
    ].contains(word.trim().toLowerCase()),
    _ => false,
  };

  final notes = switch (json['flavorNotes']) {
    final List<Object?> list => [for (final note in list) ?text(note)],
    final String line => _notesFrom(line),
    _ => const <String>[],
  };

  String? shopUrl;
  if (field('shopUrl') case final url?) {
    shopUrl = httpsLink(url);
    if (shopUrl == null) dropped.add('shopUrl');
  }

  double? number(String key) {
    final value = json[key];
    if (value == null) return null;
    final parsed = switch (value) {
      final num n => n.toDouble(),
      final String s => _cardNumber(s, price: key == 'price'),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      dropped.add(key);
      return null;
    }
    return parsed;
  }

  final price = number('price');
  int? priceCents;
  if (price != null) {
    final cents = price * 100;
    // Stay inside the exact integer range shared by native and web targets.
    if (cents.isFinite && cents <= 9007199254740991) {
      priceCents = cents.round();
    } else {
      dropped.add('price');
    }
  }
  final bagGrams = number('bagGrams');

  String? roastDate;
  if (field('roastDate') case final date?) {
    final parsed = DateTime.tryParse(date);
    if (parsed != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
        parsed.year > 0 &&
        parsed.year == int.parse(date.substring(0, 4)) &&
        parsed.month == int.parse(date.substring(5, 7)) &&
        parsed.day == int.parse(date.substring(8, 10))) {
      roastDate = date;
    } else {
      dropped.add('roastDate');
    }
  }

  SharedOrigin origin(Map<String, Object?> map) {
    final range = parseAltitude(map['altitudeMeters']);
    final low = range?.$1;
    final upper = map['altitudeMaxMeters'];
    final high = upper == null ? range?.$2 : parseAltitude(upper)?.$1;
    final valid = validAltitudeRange(low, high);
    if ((map['altitudeMeters'] != null && range == null) ||
        !valid ||
        (upper != null && parseAltitude(upper) == null)) {
      dropped.add('altitudeMeters');
    }
    return SharedOrigin(
      country: text(map['country']),
      region: text(map['region']),
      farm: text(map['farm']),
      producer: text(map['producer']),
      variety: text(map['variety']),
      process: text(map['process']),
      altitudeMeters: low,
      altitudeMaxMeters: valid ? high : null,
      harvest: text(map['harvest']),
    );
  }

  final origins = switch (json['origins']) {
    final List<Object?> list => [
      for (final item in list)
        if (item case final Map<String, Object?> map) origin(map),
    ],
    // An AI may put a single origin's fields on the coffee itself.
    _ => [origin(json)],
  }.where((origin) => !origin.isEmpty).toList();

  return ReadBean(
    SharedBean(
      name: name,
      roaster: field('roaster') ?? '',
      roastLevel: roastLevel,
      decaf: decaf,
      flavorNotes: notes,
      shopUrl: shopUrl,
      priceCents: priceCents,
      bagGrams: bagGrams,
      roastDate: roastDate,
      origins: origins,
    ),
    dropped: dropped,
  );
}

double? _cardNumber(String source, {required bool price}) {
  final suffix = price ? r'(?:€|eur|euros?)?' : r'(?:g|grams?|gramos?)?';
  final match = RegExp(
    r'^([0-9]+(?:[.,][0-9]+)?)\s*' + suffix + r'$',
    caseSensitive: false,
  ).firstMatch(source.trim());
  return match == null ? null : double.tryParse(match[1]!.replaceAll(',', '.'));
}

List<String> _notesFrom(String? profile) => [
  for (final note in (profile ?? '').split(','))
    if (note.trim().isNotEmpty) note.trim(),
];

/// The coffee in [coffees] that [bean] already is: same name and roaster,
/// ignoring case, accents and spacing.
ExistingCoffee? existingCoffee(
  SharedBean bean,
  Iterable<ExistingCoffee> coffees,
) {
  final key = (_plain(bean.name), _plain(bean.roaster));
  return coffees
      .where((coffee) => (_plain(coffee.name), _plain(coffee.roaster)) == key)
      .firstOrNull;
}

String _plain(String text) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final lower = text.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}
