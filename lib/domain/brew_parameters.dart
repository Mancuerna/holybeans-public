/// Groups of brew parameters, in the order the form, the details and the
/// shared text follow.
enum BrewParameterGroup { coffee, recipe, equipment, timing, pours, result }

/// Everything a brew can show or share. Hiding a parameter only hides it:
/// imports, the machine, the scale and "Repeat" still fill it, and editing
/// keeps its value.
///
/// The names are stored in preferences. They keep the earlier names of the
/// hideable fields (`bloom` is the total bloom time) and of the shared ones,
/// so existing choices still apply.
enum BrewParameter {
  // Coffee: only shared; the brew always shows its coffee and method.
  coffee(BrewParameterGroup.coffee, canHide: false),
  roaster(BrewParameterGroup.coffee, canHide: false),
  country(BrewParameterGroup.coffee, canHide: false),
  region(BrewParameterGroup.coffee, canHide: false),
  variety(BrewParameterGroup.coffee, canHide: false),
  process(BrewParameterGroup.coffee, canHide: false),
  farm(BrewParameterGroup.coffee, canHide: false),
  producer(BrewParameterGroup.coffee, canHide: false),
  altitude(BrewParameterGroup.coffee, canHide: false),
  harvest(BrewParameterGroup.coffee, canHide: false),
  roastLevel(BrewParameterGroup.coffee, canHide: false),
  flavorNotes(BrewParameterGroup.coffee, canHide: false),
  date(BrewParameterGroup.coffee, canHide: false),
  method(BrewParameterGroup.coffee, canHide: false),
  // Recipe. Without the dose a brew means nothing, so it always shows.
  dose(BrewParameterGroup.recipe, canHide: false),
  water(BrewParameterGroup.recipe),
  beverage(BrewParameterGroup.recipe),
  ratio(BrewParameterGroup.recipe),
  temperature(BrewParameterGroup.recipe),
  // Equipment.
  grinder(BrewParameterGroup.equipment),
  grindSetting(BrewParameterGroup.equipment),
  grindRpm(BrewParameterGroup.equipment),
  feederRpm(BrewParameterGroup.equipment),
  tools(BrewParameterGroup.equipment),
  waterProfile(BrewParameterGroup.equipment),
  profile(BrewParameterGroup.equipment),
  // Timing. The time drives the timer and the scale, so it always shows.
  time(BrewParameterGroup.timing, canHide: false),
  preinfusion(BrewParameterGroup.timing),
  firstDrip(BrewParameterGroup.timing),
  pressure(BrewParameterGroup.timing),
  // Filter pours.
  bloomCount(BrewParameterGroup.pours),
  bloom(BrewParameterGroup.pours),
  pourCount(BrewParameterGroup.pours),
  pourDetails(BrewParameterGroup.pours),
  // Result.
  tds(BrewParameterGroup.result),
  ey(BrewParameterGroup.result),
  rating(BrewParameterGroup.result),
  notes(BrewParameterGroup.result),
  cost(BrewParameterGroup.result, canHide: false),
  photos(BrewParameterGroup.result, canShare: false);

  const BrewParameter(this.group, {this.canHide = true, this.canShare = true});

  final BrewParameterGroup group;

  /// Whether Settings can hide it from the form, details and lists.
  final bool canHide;

  /// Whether it can be part of the shared text or image.
  final bool canShare;

  /// The coffee's own fields are shared but never part of a brew's view.
  bool get isBrewField => group != BrewParameterGroup.coffee;

  static BrewParameter? byName(String name) =>
      values.where((value) => value.name == name).firstOrNull;
}

/// What the "Essentials" preset hides from the form, the details and the
/// history: the finer equipment, timing, pour and measurement fields. The
/// recipe, grind, rating, notes and photos stay. Hiding never deletes data.
const Set<BrewParameter> essentialHiddenParameters = {
  BrewParameter.grindRpm,
  BrewParameter.feederRpm,
  BrewParameter.tools,
  BrewParameter.waterProfile,
  BrewParameter.profile,
  BrewParameter.preinfusion,
  BrewParameter.firstDrip,
  BrewParameter.pressure,
  BrewParameter.bloomCount,
  BrewParameter.bloom,
  BrewParameter.pourCount,
  BrewParameter.pourDetails,
  BrewParameter.tds,
  BrewParameter.ey,
};

/// Shared by default on a new install: descriptive fields, not personal ones.
final Set<BrewParameter> defaultSharedParameters = {
  for (final parameter in BrewParameter.values)
    if (parameter.canShare &&
        !{
          BrewParameter.date,
          BrewParameter.rating,
          BrewParameter.notes,
          BrewParameter.farm,
          BrewParameter.producer,
          BrewParameter.altitude,
          BrewParameter.harvest,
          BrewParameter.roastLevel,
          BrewParameter.flavorNotes,
          BrewParameter.cost,
          BrewParameter.grindRpm,
          BrewParameter.feederRpm,
          BrewParameter.tools,
          BrewParameter.waterProfile,
          BrewParameter.profile,
          BrewParameter.bloomCount,
          BrewParameter.bloom,
          BrewParameter.pourCount,
          BrewParameter.pourDetails,
        }.contains(parameter))
      parameter,
};

/// Parameters that became shareable with the unified list and are turned on
/// for people who had already chosen what to share.
const newlySharedParameters = {
  BrewParameter.ratio,
  BrewParameter.grindSetting,
  BrewParameter.preinfusion,
  BrewParameter.firstDrip,
  BrewParameter.pressure,
};

/// Marks a stored share list written with the unified parameters. Earlier
/// versions ignore unknown names, so it is safe in the same list.
const sharedParametersMarker = '_parameters-v2';

/// Reads stored hidden names; unknown or unhideable ones are dropped.
Set<BrewParameter> decodeHiddenParameters(Iterable<String> names) => {
  for (final name in names)
    if (BrewParameter.byName(name) case final parameter? when parameter.canHide)
      parameter,
};

/// Reads stored shared names. A list from before the unified parameters
/// gains [newlySharedParameters]; an empty one falls back to the defaults.
Set<BrewParameter> decodeSharedParameters(List<String> names) {
  final shared = {
    for (final name in names)
      if (BrewParameter.byName(name) case final parameter?
          when parameter.canShare)
        parameter,
  };
  if (shared.isEmpty) return {...defaultSharedParameters};
  if (!names.contains(sharedParametersMarker)) {
    shared.addAll(newlySharedParameters);
  }
  return shared;
}

/// The stored form of [shared], in display order and with the marker.
List<String> encodeSharedParameters(Set<BrewParameter> shared) => [
  sharedParametersMarker,
  for (final parameter in BrewParameter.values)
    if (parameter.canShare && shared.contains(parameter)) parameter.name,
];
