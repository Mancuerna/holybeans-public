enum ConsumptionSource { grinder, preGround, unknown }

typedef ConsumptionDose = ({
  String? grinderId,
  String? grinderName,
  bool isPreGround,
  double? grams,
  int brewedAtMs,
});

class GrinderConsumption {
  const GrinderConsumption({
    required this.source,
    required this.name,
    required this.grams,
    required this.brewCount,
    required this.doseCount,
  });

  final ConsumptionSource source;
  final String? name;
  final double grams;
  final int brewCount;
  final int doseCount;
}

List<GrinderConsumption> consumptionByGrinder(Iterable<ConsumptionDose> doses) {
  final groups = <(ConsumptionSource, String?), List<ConsumptionDose>>{};
  for (final dose in doses) {
    final name = dose.grinderName?.trim();
    final source = dose.isPreGround
        ? ConsumptionSource.preGround
        : dose.grinderId != null || (name != null && name.isNotEmpty)
        ? ConsumptionSource.grinder
        : ConsumptionSource.unknown;
    // IDs survive renames; older imports may only have the name.
    final identity = source == ConsumptionSource.grinder
        ? dose.grinderId != null
              ? 'id:${dose.grinderId}'
              : 'name:$name'
        : null;
    groups.putIfAbsent((source, identity), () => []).add(dose);
  }
  final result = <GrinderConsumption>[];
  for (final entry in groups.entries) {
    final values = entry.value;
    final named =
        values
            .where((dose) => dose.grinderName?.trim().isNotEmpty ?? false)
            .toList()
          ..sort((a, b) => b.brewedAtMs.compareTo(a.brewedAtMs));
    final known = values.where(
      (dose) => dose.grams != null && dose.grams!.isFinite && dose.grams! > 0,
    );
    result.add(
      GrinderConsumption(
        source: entry.key.$1,
        name: named.isEmpty ? null : named.first.grinderName!.trim(),
        grams: known.fold(0, (sum, dose) => sum + dose.grams!),
        brewCount: values.length,
        doseCount: known.length,
      ),
    );
  }
  result.sort((a, b) {
    final byGrams = b.grams.compareTo(a.grams);
    return byGrams != 0
        ? byGrams
        : (a.name ?? a.source.name).compareTo(b.name ?? b.source.name);
  });
  return List.unmodifiable(result);
}

/// A grinder's use as its card sums it up: how many brews, the last one,
/// and the setting it is most often at for each method (ties go to the most
/// recent), methods ordered by how often they use it.
typedef GrinderUse = ({
  int brewCount,
  int? lastBrewedAtMs,
  List<({String method, String setting})> usualSettings,
});

GrinderUse grinderUse(
  Iterable<({String method, String? setting, int brewedAtMs})> brews,
) {
  var count = 0;
  int? last;
  final byMethod = <String, Map<String, ({int count, int latest})>>{};
  final methodCounts = <String, int>{};
  for (final brew in brews) {
    count++;
    if (last == null || brew.brewedAtMs > last) last = brew.brewedAtMs;
    methodCounts[brew.method] = (methodCounts[brew.method] ?? 0) + 1;
    final setting = brew.setting?.trim();
    if (setting == null || setting.isEmpty) continue;
    final settings = byMethod.putIfAbsent(brew.method, () => {});
    final seen = settings[setting];
    settings[setting] = (
      count: (seen?.count ?? 0) + 1,
      latest: seen == null || brew.brewedAtMs > seen.latest
          ? brew.brewedAtMs
          : seen.latest,
    );
  }
  final methods = byMethod.keys.toList()
    ..sort((a, b) => methodCounts[b]!.compareTo(methodCounts[a]!));
  return (
    brewCount: count,
    lastBrewedAtMs: last,
    usualSettings: [
      for (final method in methods)
        (
          method: method,
          setting:
              (byMethod[method]!.entries.toList()..sort((a, b) {
                    final byCount = b.value.count.compareTo(a.value.count);
                    return byCount != 0
                        ? byCount
                        : b.value.latest.compareTo(a.value.latest);
                  }))
                  .first
                  .key,
        ),
    ],
  );
}
