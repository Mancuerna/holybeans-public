import 'dart:math' as math;

import 'package:holybeans/domain/water_chemistry.dart';

// Five nonnegative variables expressed in GH or alkalinity contribution.
// Enumerate active salts and solve each equality-constrained least-squares
// problem. GH/KH deficits are exact; known ions decide among those solutions.
Map<WaterSalt, double> adjustWater({
  required WaterComposition base,
  required WaterComposition target,
  required double litres,
  required CalciumForm calcium,
  Set<WaterSalt> allowed = const {...WaterSalt.values},
  bool allowPartial = false,
}) {
  if (base.gh == null ||
      base.kh == null ||
      target.gh == null ||
      target.kh == null ||
      !litres.isFinite ||
      litres <= 0) {
    throw ArgumentError('Incomplete water adjustment');
  }
  final deficits = [
    math.max(0.0, target.gh! - base.gh!),
    math.max(0.0, target.kh! - base.kh!),
  ];
  if (allowPartial) {
    for (var group = 0; group < 2; group++) {
      if (!allowed.any((salt) => (salt.contributesGh ? 0 : 1) == group)) {
        deficits[group] = 0;
      }
    }
  }
  const salts = WaterSalt.values;
  final factors = [
    for (final salt in salts)
      salt.contributesGh
          ? saltContribution(salt, calcium, 1).gh!
          : saltContribution(salt, calcium, 1).kh!,
  ];
  final columns = [
    for (var i = 0; i < salts.length; i++)
      saltContribution(salts[i], calcium, 1 / factors[i]),
  ];
  final rows = <List<double>>[];
  final desired = <double>[];
  for (final ion in WaterIon.values) {
    final initial = base[ion];
    final goal = target[ion];
    if (initial == null || goal == null) continue;
    final scale = math.max(5.0, goal);
    rows.add([for (final column in columns) column[ion]! / scale]);
    desired.add((goal - initial) / scale);
  }
  final q = List.generate(5, (_) => List.filled(5, 0.0));
  final b = List.filled(5, 0.0);
  for (var i = 0; i < 5; i++) {
    for (var r = 0; r < rows.length; r++) {
      b[i] += rows[r][i] * desired[r];
      for (var j = 0; j < 5; j++) {
        q[i][j] += rows[r][i] * rows[r][j];
      }
    }
    // Stable tie-break for incomplete labels; negligible against ion errors.
    q[i][i] += 1e-9;
  }
  List<double>? best;
  var bestScore = double.infinity;
  for (var mask = 0; mask < 32; mask++) {
    final active = [
      for (var i = 0; i < 5; i++)
        if ((mask & (1 << i)) != 0) i,
    ];
    if (active.any(
      (i) =>
          !allowed.contains(salts[i]) ||
          deficits[salts[i].contributesGh ? 0 : 1] < 1e-10,
    )) {
      continue;
    }
    final groups = [
      for (var g = 0; g < 2; g++)
        if (deficits[g] >= 1e-10) g,
    ];
    if (groups.any(
      (g) => !active.any((i) => (salts[i].contributesGh ? 0 : 1) == g),
    )) {
      continue;
    }
    if (active.isEmpty) {
      best = List.filled(5, 0);
      break;
    }
    final n = active.length;
    final size = n + groups.length;
    final matrix = List.generate(size, (_) => List.filled(size, 0.0));
    final rhs = List.filled(size, 0.0);
    for (var a = 0; a < n; a++) {
      rhs[a] = b[active[a]];
      for (var c = 0; c < n; c++) {
        matrix[a][c] = q[active[a]][active[c]];
      }
      for (var g = 0; g < groups.length; g++) {
        final value = (salts[active[a]].contributesGh ? 0 : 1) == groups[g]
            ? 1.0
            : 0.0;
        matrix[a][n + g] = value;
        matrix[n + g][a] = value;
      }
    }
    for (var g = 0; g < groups.length; g++) {
      rhs[n + g] = deficits[groups[g]];
    }
    final solved = _solve(matrix, rhs);
    if (solved == null || solved.take(n).any((v) => !v.isFinite || v < -1e-7)) {
      continue;
    }
    final amounts = List.filled(5, 0.0);
    for (var a = 0; a < n; a++) {
      amounts[active[a]] = math.max(0, solved[a]);
    }
    var score = 0.0;
    for (var r = 0; r < rows.length; r++) {
      var value = -desired[r];
      for (var i = 0; i < 5; i++) {
        value += rows[r][i] * amounts[i];
      }
      score += value * value;
    }
    score += amounts.fold<double>(0, (s, x) => s + 1e-9 * x * x);
    if (score < bestScore) {
      bestScore = score;
      best = amounts;
    }
  }
  if (best == null) {
    throw ArgumentError('Selected salts cannot reach GH/KH deficits');
  }
  return {for (var i = 0; i < 5; i++) salts[i]: best[i] / factors[i] * litres};
}

// Preserve the requested Ca/Mg split whenever both deficits are reachable.
// Otherwise retain the GH/KH priority of the existing adjustment.
Map<WaterSalt, double> adjustWaterMixture({
  required WaterComposition base,
  required WaterComposition target,
  required double litres,
  required CalciumForm calcium,
  required WaterSalt magnesiumSource,
  required WaterSalt khSource,
  Set<WaterSalt> allowed = const {...WaterSalt.values},
}) {
  if (magnesiumSource.group != WaterSaltGroup.magnesium ||
      khSource.contributesGh ||
      !litres.isFinite ||
      litres <= 0 ||
      base.kh == null ||
      target.kh == null ||
      base.gh == null ||
      target.gh == null) {
    throw ArgumentError('Invalid mixture adjustment');
  }
  final grams = <WaterSalt, double>{};
  for (final (ion, salt) in [
    (WaterIon.calcium, WaterSalt.calciumChloride),
    (WaterIon.magnesium, magnesiumSource),
  ]) {
    final initial = base[ion];
    final goal = target[ion];
    if (initial == null || goal == null) {
      throw ArgumentError('Missing calcium or magnesium');
    }
    grams[salt] =
        math.max(0, goal - initial) /
        saltContribution(salt, calcium, 1)[ion]! *
        litres;
  }
  final addition = waterFromSalts(grams, litres, calcium);
  if ((base.gh! + addition.gh! - target.gh!).abs() > .01 ||
      grams.entries.any((e) => e.value > 0 && !allowed.contains(e.key)) ||
      !allowed.contains(khSource)) {
    return adjustWater(
      base: base,
      target: target,
      litres: litres,
      calcium: calcium,
      allowed: {
        WaterSalt.calciumChloride,
        magnesiumSource,
        khSource,
      }.intersection(allowed),
      allowPartial: true,
    );
  }
  grams[khSource] =
      math.max(0, target.kh! - base.kh!) /
      saltContribution(khSource, calcium, 1).kh! *
      litres;
  return grams;
}

// Meet reachable Ca, Mg and KH deficits exactly. Among these solutions, fit
// only the optional ions with known starting values. Missing salt groups and
// initial excesses remain visible in the result rather than inventing removal.
Map<WaterSalt, double> adjustWaterToIons({
  required WaterComposition base,
  required WaterComposition target,
  required double litres,
  required CalciumForm calcium,
  required Set<WaterSalt> allowed,
}) {
  final initial = [base[WaterIon.magnesium], base[WaterIon.calcium], base.kh];
  final goals = [
    target[WaterIon.magnesium],
    target[WaterIon.calcium],
    target.kh,
  ];
  if (!litres.isFinite ||
      litres <= 0 ||
      initial.contains(null) ||
      goals.contains(null)) {
    throw ArgumentError('Missing primary water composition');
  }
  int group(WaterSalt salt) => switch (salt.group) {
    WaterSaltGroup.magnesium => 0,
    WaterSaltGroup.calcium => 1,
    WaterSaltGroup.alkalinity => 2,
  };
  final deficits = [
    for (var g = 0; g < 3; g++)
      allowed.any((s) => group(s) == g)
          ? math.max(0.0, goals[g]! - initial[g]!)
          : 0.0,
  ];
  const salts = WaterSalt.values;
  final factors = [
    for (final salt in salts)
      switch (group(salt)) {
        0 => saltContribution(salt, calcium, 1)[WaterIon.magnesium]!,
        1 => saltContribution(salt, calcium, 1)[WaterIon.calcium]!,
        _ => saltContribution(salt, calcium, 1).kh!,
      },
  ];
  final rows = <List<double>>[];
  final desired = <double>[];
  for (final ion in WaterIon.values) {
    if (ion == WaterIon.calcium ||
        ion == WaterIon.magnesium ||
        base[ion] == null ||
        target[ion] == null) {
      continue;
    }
    final scale = math.max(5.0, target[ion]!);
    rows.add([
      for (var i = 0; i < salts.length; i++)
        saltContribution(salts[i], calcium, 1 / factors[i])[ion]! / scale,
    ]);
    desired.add((target[ion]! - base[ion]!) / scale);
  }
  List<double>? best;
  var bestScore = double.infinity;
  for (var mask = 0; mask < 32; mask++) {
    final active = [
      for (var i = 0; i < 5; i++)
        if (mask & (1 << i) != 0) i,
    ];
    if (active.any(
      (i) => !allowed.contains(salts[i]) || deficits[group(salts[i])] < 1e-10,
    )) {
      continue;
    }
    final groups = [
      for (var g = 0; g < 3; g++)
        if (deficits[g] >= 1e-10) g,
    ];
    if (groups.any((g) => !active.any((i) => group(salts[i]) == g))) continue;
    if (active.isEmpty) {
      best = List.filled(5, 0);
      break;
    }
    final n = active.length;
    final matrix = List.generate(
      n + groups.length,
      (_) => List.filled(n + groups.length, 0.0),
    );
    final rhs = List.filled(n + groups.length, 0.0);
    for (var a = 0; a < n; a++) {
      for (var r = 0; r < rows.length; r++) {
        rhs[a] += rows[r][active[a]] * desired[r];
        for (var b = 0; b < n; b++) {
          matrix[a][b] += rows[r][active[a]] * rows[r][active[b]];
        }
      }
      matrix[a][a] += 1e-9;
      for (var g = 0; g < groups.length; g++) {
        final coefficient = group(salts[active[a]]) == groups[g] ? 1.0 : 0.0;
        matrix[a][n + g] = coefficient;
        matrix[n + g][a] = coefficient;
      }
    }
    for (var g = 0; g < groups.length; g++) {
      rhs[n + g] = deficits[groups[g]];
    }
    final solved = _solve(matrix, rhs);
    if (solved == null || solved.take(n).any((v) => !v.isFinite || v < -1e-7)) {
      continue;
    }
    final values = List.filled(5, 0.0);
    for (var a = 0; a < n; a++) {
      values[active[a]] = math.max(0.0, solved[a]);
    }
    var score = values.fold<double>(0, (sum, v) => sum + 1e-9 * v * v);
    for (var r = 0; r < rows.length; r++) {
      var error = -desired[r];
      for (var i = 0; i < 5; i++) {
        error += rows[r][i] * values[i];
      }
      score += error * error;
    }
    if (score < bestScore) {
      bestScore = score;
      best = values;
    }
  }
  if (best == null) throw ArgumentError('Unable to solve water targets');
  return {for (var i = 0; i < 5; i++) salts[i]: best[i] / factors[i] * litres};
}

List<double>? _solve(List<List<double>> matrix, List<double> rhs) {
  final n = rhs.length;
  final a = [
    for (var i = 0; i < n; i++) [...matrix[i], rhs[i]],
  ];
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final row = a[col];
    a[col] = a[pivot];
    a[pivot] = row;
    final divisor = a[col][col];
    for (var c = col; c <= n; c++) {
      a[col][c] /= divisor;
    }
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final multiplier = a[r][col];
      for (var c = col; c <= n; c++) {
        a[r][c] -= multiplier * a[col][c];
      }
    }
  }
  return [for (var i = 0; i < n; i++) a[i][n]];
}
