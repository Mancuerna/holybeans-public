import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/share_markdown.dart';

enum ShareTemplateStyle { espresso, filter }

// A null parameter denotes a tag calculated from the brew's lot.
const shareTemplateTags = <String, BrewParameter?>{
  'coffee': BrewParameter.coffee,
  'roaster': BrewParameter.roaster,
  'country': BrewParameter.country,
  'country_flag': BrewParameter.country,
  'region': BrewParameter.region,
  'variety': BrewParameter.variety,
  'process': BrewParameter.process,
  'farm': BrewParameter.farm,
  'producer': BrewParameter.producer,
  'altitude': BrewParameter.altitude,
  'harvest': BrewParameter.harvest,
  'roast_level': BrewParameter.roastLevel,
  'days_from_roast': null,
  'flavor_notes': BrewParameter.flavorNotes,
  'cost': BrewParameter.cost,
  'date': BrewParameter.date,
  'method': BrewParameter.method,
  'dose': BrewParameter.dose,
  'water': BrewParameter.water,
  'beverage': BrewParameter.beverage,
  'ratio': BrewParameter.ratio,
  'brew_temp': BrewParameter.temperature,
  'grinder': BrewParameter.grinder,
  'grind_setting': BrewParameter.grindSetting,
  'grind_rpm': BrewParameter.grindRpm,
  'feeder_rpm': BrewParameter.feederRpm,
  'tools': BrewParameter.tools,
  'water_profile': BrewParameter.waterProfile,
  'profile': BrewParameter.profile,
  'time': BrewParameter.time,
  'preinfusion': BrewParameter.preinfusion,
  'first_drip': BrewParameter.firstDrip,
  'pressure': BrewParameter.pressure,
  'bloom_count': BrewParameter.bloomCount,
  'bloom': BrewParameter.bloom,
  'pour_count': BrewParameter.pourCount,
  'pour_details': BrewParameter.pourDetails,
  'tds': BrewParameter.tds,
  'ey': BrewParameter.ey,
  'rating': BrewParameter.rating,
  'notes': BrewParameter.notes,
};

class ShareTemplate {
  const ShareTemplate({
    required this.id,
    required this.name,
    required this.style,
    required this.body,
  });

  final String id;
  final String name;
  final ShareTemplateStyle style;
  final String body;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'style': style.name,
    'body': body,
  };

  static ShareTemplate fromJson(Map<String, dynamic> json) => ShareTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    style: ShareTemplateStyle.values.byName(json['style'] as String),
    body: json['body'] as String,
  );

  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 80 ||
        body.trim().isEmpty ||
        body.length > 8000 ||
        TemplateEngine.unknownTags(body).isNotEmpty) {
      throw const FormatException('Invalid share template');
    }
  }
}

class TemplateEngine {
  static final _tag = RegExp(r'<([a-zA-Z][a-zA-Z0-9_]*)>');

  static Set<String> tags(String body) => {
    for (final match in _tag.allMatches(body)) match.group(1)!,
  };

  static Set<String> unknownTags(String body, {Set<String>? allowedTags}) =>
      tags(body).difference(allowedTags ?? shareTemplateTags.keys.toSet());

  static Set<String> missingTags(
    String body,
    Map<String, String> values, {
    Set<String>? allowedTags,
  }) => {
    for (final tag in tags(body))
      if ((allowedTags ?? shareTemplateTags.keys.toSet()).contains(tag) &&
          (values[tag]?.trim().isEmpty ?? true))
        tag,
  };

  static String renderMarkdown(
    String body,
    Map<String, String> values, {
    Set<String>? allowedTags,
  }) => render(
    body,
    values.map((key, value) => MapEntry(key, ShareMarkdown.escape(value))),
    allowedTags: allowedTags,
  );

  // Single-pass substitution: tags in user data are never evaluated again.
  static String render(
    String body,
    Map<String, String> values, {
    Set<String>? allowedTags,
  }) => body.replaceAllMapped(_tag, (match) {
    final tag = match.group(1)!;
    if (!(allowedTags ?? shareTemplateTags.keys.toSet()).contains(tag)) {
      return match.group(0)!;
    }
    final value = values[tag];
    return value == null || value.trim().isEmpty ? '—' : value;
  });
}

String shareTemplateCountryFlags(Iterable<String?> countries) => {
  for (final name in countries)
    if (coffeeCountryFor(name) case final country?) country.flag,
}.join(' ');
