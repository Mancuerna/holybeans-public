import 'package:holybeans/domain/text_suggestions.dart';

/// Visual families chosen by HolyBeans, independent of any official wheel.
enum FlavorTone { red, pink, purple, blue, orange, yellow, green, cream, brown }

/// Exact bilingual aliases; labels live in the application localizations.
enum FlavorDescriptor {
  strawberry(FlavorTone.red, ['strawberry', 'fresa', 'frutilla']),
  raspberry(FlavorTone.red, ['raspberry', 'frambuesa']),
  blackberry(FlavorTone.purple, ['blackberry', 'mora', 'zarzamora']),
  blueberry(FlavorTone.blue, ['blueberry', 'arándano', 'arándano azul']),
  blackcurrant(FlavorTone.purple, [
    'blackcurrant',
    'grosella negra',
    'black currant',
  ]),
  redcurrant(FlavorTone.red, ['redcurrant', 'grosella roja', 'red currant']),
  cherry(FlavorTone.red, ['cherry', 'cereza']),
  apple(FlavorTone.green, ['apple', 'manzana']),
  pear(FlavorTone.green, ['pear', 'pera']),
  peach(FlavorTone.orange, ['peach', 'melocotón', 'durazno']),
  apricot(FlavorTone.orange, ['apricot', 'albaricoque', 'damasco']),
  nectarine(FlavorTone.orange, ['nectarine', 'nectarina']),
  plum(FlavorTone.purple, ['plum', 'ciruela']),
  grape(FlavorTone.purple, ['grape', 'uva']),
  raisin(FlavorTone.brown, ['raisin', 'pasa', 'pasas']),
  prune(FlavorTone.purple, ['prune', 'ciruela pasa']),
  fig(FlavorTone.purple, ['fig', 'higo']),
  date(FlavorTone.brown, ['date', 'dátil']),
  pomegranate(FlavorTone.red, ['pomegranate', 'granada']),
  orange(FlavorTone.orange, ['orange', 'naranja']),
  mandarin(FlavorTone.orange, ['mandarin', 'mandarina', 'mandarin orange']),
  lemon(FlavorTone.yellow, ['lemon', 'limón']),
  lime(FlavorTone.green, ['lime', 'lima']),
  grapefruit(FlavorTone.pink, ['grapefruit', 'pomelo', 'toronja']),
  bergamot(FlavorTone.yellow, ['bergamot', 'bergamota']),
  citrus(FlavorTone.yellow, ['citrus', 'cítricos', 'citrus fruit', 'cítrico']),
  mango(FlavorTone.orange, ['mango']),
  pineapple(FlavorTone.yellow, ['pineapple', 'piña', 'ananás']),
  papaya(FlavorTone.orange, ['papaya']),
  passionFruit(FlavorTone.yellow, [
    'passion fruit',
    'fruta de la pasión',
    'maracuyá',
    'parchita',
  ]),
  banana(FlavorTone.yellow, ['banana', 'plátano']),
  coconut(FlavorTone.cream, ['coconut', 'coco']),
  lychee(FlavorTone.pink, ['lychee', 'lichi', 'litchi']),
  guava(FlavorTone.pink, ['guava', 'guayaba']),
  floral(FlavorTone.pink, ['floral', 'flores']),
  jasmine(FlavorTone.cream, ['jasmine', 'jazmín']),
  rose(FlavorTone.pink, ['rose', 'rosa']),
  chamomile(FlavorTone.yellow, ['chamomile', 'manzanilla', 'camomile']),
  orangeBlossom(FlavorTone.cream, [
    'orange blossom',
    'azahar',
    'flor de azahar',
  ]),
  lavender(FlavorTone.purple, ['lavender', 'lavanda']),
  hibiscus(FlavorTone.red, ['hibiscus', 'hibisco', 'flor de jamaica']),
  caramel(FlavorTone.orange, ['caramel', 'caramelo']),
  honey(FlavorTone.yellow, ['honey', 'miel']),
  brownSugar(FlavorTone.brown, [
    'brown sugar',
    'azúcar moreno',
    'azúcar morena',
  ]),
  molasses(FlavorTone.brown, ['molasses', 'melaza']),
  mapleSyrup(FlavorTone.brown, [
    'maple syrup',
    'sirope de arce',
    'jarabe de arce',
  ]),
  vanilla(FlavorTone.cream, ['vanilla', 'vainilla']),
  chocolate(FlavorTone.brown, ['chocolate']),
  darkChocolate(FlavorTone.brown, [
    'dark chocolate',
    'chocolate negro',
    'chocolate amargo',
  ]),
  milkChocolate(FlavorTone.brown, ['milk chocolate', 'chocolate con leche']),
  cocoa(FlavorTone.brown, ['cocoa', 'cacao']),
  almond(FlavorTone.cream, ['almond', 'almendra']),
  hazelnut(FlavorTone.brown, ['hazelnut', 'avellana']),
  walnut(FlavorTone.brown, ['walnut', 'nuez', 'nueces']),
  peanut(FlavorTone.brown, ['peanut', 'cacahuete', 'maní', 'peanuts']),
  nutty(FlavorTone.brown, ['nutty', 'frutos secos']),
  cinnamon(FlavorTone.brown, ['cinnamon', 'canela']),
  clove(FlavorTone.brown, ['clove', 'clavo']),
  nutmeg(FlavorTone.brown, ['nutmeg', 'nuez moscada']),
  anise(FlavorTone.cream, ['anise', 'anís']),
  pepper(FlavorTone.brown, ['pepper', 'pimienta']),
  blackTea(FlavorTone.brown, ['black tea', 'té negro']),
  greenTea(FlavorTone.green, ['green tea', 'té verde']),
  herbal(FlavorTone.green, ['herbal', 'hierbas', 'herb-like']),
  woody(FlavorTone.brown, ['woody', 'madera']),
  tobacco(FlavorTone.brown, ['tobacco', 'tabaco']),
  fermented(FlavorTone.purple, ['fermented', 'fermentado']),
  winey(FlavorTone.purple, ['winey', 'vinoso', 'wine', 'vino']),
  smoky(FlavorTone.brown, ['smoky', 'ahumado']);

  const FlavorDescriptor(this.tone, this.aliases);
  final FlavorTone tone;
  final List<String> aliases;
}

final _descriptorsByAlias = {
  for (final descriptor in FlavorDescriptor.values)
    for (final alias in descriptor.aliases) foldSuggestion(alias): descriptor,
};

/// Recognizes whole notes only: “lemon cake” remains free text.
FlavorDescriptor? recognizeFlavorNote(String note) =>
    _descriptorsByAlias[foldSuggestion(note)];

/// The colour family of a note: its descriptor's, or for free text the one
/// of a descriptor named inside it ("Cherry jam" is red, "flowers" pink),
/// so every note on a card is coloured by the same rule. Identity and
/// labels stay with [recognizeFlavorNote].
FlavorTone? flavorNoteTone(String note) {
  if (recognizeFlavorNote(note) case final descriptor?) return descriptor.tone;
  final words = foldSuggestion(note)
      .split(RegExp(r'[\s\-/]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  FlavorDescriptor? find(String text) =>
      _descriptorsByAlias[text] ??
      (text.endsWith('ies')
          ? _descriptorsByAlias['${text.substring(0, text.length - 3)}y']
          : null) ??
      (text.endsWith('es')
          ? _descriptorsByAlias[text.substring(0, text.length - 2)]
          : null) ??
      (text.endsWith('s')
          ? _descriptorsByAlias[text.substring(0, text.length - 1)]
          : null);
  // Two-word names first ("brown sugar"), then single words.
  for (final size in [2, 1]) {
    for (var i = 0; i + size <= words.length; i++) {
      if (find(words.sublist(i, i + size).join(' ')) case final found?) {
        return found.tone;
      }
    }
  }
  // "Flowers", "flores": the floral family by its root.
  if (words.any((word) => word.startsWith('flower') || word == 'flor')) {
    return FlavorDescriptor.floral.tone;
  }
  return null;
}

String flavorNoteIdentity(String note) =>
    recognizeFlavorNote(note)?.name ?? foldSuggestion(note);

List<String> splitFlavorNotes(String source) => [
  for (final part in source.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

/// Adds a new note without rewriting existing notes, including imported aliases.
List<String> appendFlavorNote(List<String> notes, String note) {
  final trimmed = note.trim();
  if (trimmed.isEmpty ||
      notes.any(
        (existing) =>
            flavorNoteIdentity(existing) == flavorNoteIdentity(trimmed),
      )) {
    return List.of(notes);
  }
  return [...notes, trimmed];
}

/// Finds descriptors by prefix in either language, excluding selected aliases.
List<FlavorDescriptor> suggestFlavorNotes(String query, List<String> selected) {
  final folded = foldSuggestion(query);
  if (folded.isEmpty) return const [];
  final used = selected.map(recognizeFlavorNote).toSet();
  return FlavorDescriptor.values
      .where(
        (descriptor) =>
            !used.contains(descriptor) &&
            descriptor.aliases.any(
              (alias) => foldSuggestion(alias).startsWith(folded),
            ),
      )
      .take(5)
      .toList();
}
