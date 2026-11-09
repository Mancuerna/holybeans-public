import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/planned_brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

class BrewPoursDraft extends ChangeNotifier {
  BrewPoursDraft({Brew? existing, Brew? repeated})
    : bloomCount = existing?.bloomCount ?? repeated?.bloomCount,
      pourCount = existing?.pourCount ?? repeated?.pourCount {
    for (final phase in BrewPours.fromStorage(
      bloomCount: existing?.bloomCount,
      pourCount: existing?.pourCount,
      phasesJson: existing?.pourPhasesJson,
    ).phases) {
      phaseDraft(phase.kind, phase.number).fill(phase);
    }
  }

  final detailsController = ExpansibleController();
  bool get detailsExpanded => detailsController.isExpanded;
  set detailsExpanded(bool value) {
    if (value) {
      detailsController.expand();
    } else {
      detailsController.collapse();
    }
  }

  bool waterPlanExpanded = false;
  double waterPlanBloomRatio = 2;
  bool waterPlanUsed = false;

  void expandWaterPlan(bool expanded) {
    waterPlanExpanded = expanded;
    if (expanded) waterPlanUsed = true;
    notifyListeners();
  }

  void setWaterPlanBloomRatio(double ratio) {
    waterPlanBloomRatio = ratio;
    notifyListeners();
  }

  PourPlan? waterPlan({required double? dose, required double? water}) {
    if (dose == null ||
        !dose.isFinite ||
        dose <= 0 ||
        water == null ||
        !water.isFinite ||
        water <= 0 ||
        bloomCount == null ||
        pourCount == null) {
      return null;
    }
    return PourPlan(
      doseGrams: dose,
      ratio: water / dose,
      pours: pourCount!,
      blooms: [
        for (var i = 0; i < bloomCount!; i++)
          BloomStep(doseMultiple: waterPlanBloomRatio, waitSeconds: 45),
      ],
    );
  }

  BrewPours valueForSave({
    required double? dose,
    required double? water,
    required bool hasCurve,
  }) {
    final recorded = value;
    if (!waterPlanUsed || fromCurve || hasCurve) return recorded;
    final plan = waterPlan(dose: dose, water: water);
    return plan == null ? recorded : fillPlannedWater(recorded, plan);
  }

  int? bloomCount;
  int? pourCount;
  final _phases = <(BrewPourKind, int), BrewPourPhaseDraft>{};

  /// Whether the blooms and pours came from the scale curve and can still
  /// be undone; any change by hand keeps them.
  bool fromCurve = false;
  int? _bloomCountBefore;
  int? _pourCountBefore;

  /// The total bloom time, when the curve filled it.
  TextEditingController? _bloomTotalFilled;
  String? _bloomTotalBefore;
  Map<(BrewPourKind, int), List<String>> _phasesBefore = const {};
  bool _pourCountTypedBefore = false;
  Map<(BrewPourKind, int), bool> _plannedWaterBefore = const {};

  /// The number of pours was typed in this form, rather than copied from
  /// the brew it repeats.
  bool _pourCountTyped = false;

  /// Counts chosen in this form constrain detection; inherited pours may adapt.
  int? get curvePourCount => _pourCountTyped ? pourCount : null;

  /// The curve may fill empty details, even when counts were chosen by hand.
  bool get takesCurve => !_phases.values.any((phase) => phase.hasValue);

  /// Fills counts, details and [bloomTotal] from the scale curve's [pours].
  ///
  /// The measured pouring and resting time replaces any previous total.
  /// The user can edit it afterwards or restore it with [undoFromCurve].
  void fillFromCurve(
    BrewPours pours, {
    TextEditingController? bloomTotal,
    bool expandDetails = true,
  }) {
    _plannedWaterBefore = {
      for (final entry in _phases.entries) entry.key: entry.value.waterFromPlan,
    };
    _phasesBefore = {
      for (final entry in _phases.entries)
        entry.key: [
          entry.value.water.text,
          entry.value.duration.text,
          entry.value.rest.text,
        ],
    };
    _pourCountTypedBefore = _pourCountTyped;
    _bloomTotalBefore = bloomTotal?.text;
    _bloomCountBefore = bloomCount;
    _pourCountBefore = pourCount;
    final bloomSeconds = pours.bloomSeconds;
    _bloomTotalFilled = bloomTotal;
    if (bloomTotal != null) {
      bloomTotal.text = bloomSeconds > 0 ? '$bloomSeconds' : '';
    }
    bloomCount = pours.bloomCount;
    pourCount = pours.pourCount;
    for (final phase in _phases.values) {
      phase.clear();
    }
    for (final phase in pours.phases) {
      phaseDraft(phase.kind, phase.number).fill(phase);
    }
    fromCurve = true;
    if (expandDetails) detailsExpanded = true;
    notifyListeners();
  }

  /// Takes back [fillFromCurve].
  void undoFromCurve() {
    _bloomTotalFilled?.text = _bloomTotalBefore ?? '';
    _bloomTotalFilled = null;
    for (final phase in _phases.values) {
      phase.clear();
    }
    for (final entry in _phasesBefore.entries) {
      final phase = phaseDraft(entry.key.$1, entry.key.$2);
      phase.water.text = entry.value[0];
      phase.duration.text = entry.value[1];
      phase.rest.text = entry.value[2];
      phase.waterFromPlan = _plannedWaterBefore[entry.key] ?? false;
    }
    _pourCountTyped = _pourCountTypedBefore;
    bloomCount = _bloomCountBefore;
    pourCount = _pourCountBefore;
    fromCurve = false;
    notifyListeners();
  }

  final _countsTouched = <BrewPourKind>{};

  /// Recalls counts only; measurements belong to the brew being made.
  void applyMemory({int? blooms, int? pours}) {
    if (fromCurve || _phases.values.any((phase) => phase.hasValue)) return;
    if (!_countsTouched.contains(BrewPourKind.bloom)) bloomCount = blooms;
    if (!_countsTouched.contains(BrewPourKind.pour)) pourCount = pours;
    notifyListeners();
  }

  /// Finishing an unmeasured plan replaces the recipe, without inventing phases.
  void applyPlan({required int blooms, required int pours}) {
    bloomCount = blooms;
    pourCount = pours;
    _countsTouched.addAll(BrewPourKind.values);
    _pourCountTyped = false;
    fromCurve = false;
    for (final phase in _phases.values) {
      phase.clear();
    }
    notifyListeners();
  }

  void setCount(BrewPourKind kind, int? count) {
    fromCurve = false;
    _countsTouched.add(kind);
    if (kind == BrewPourKind.pour) _pourCountTyped = count != null;
    BrewPours(
      bloomCount: kind == BrewPourKind.bloom ? count : bloomCount,
      pourCount: kind == BrewPourKind.pour ? count : pourCount,
    );
    if (kind == BrewPourKind.bloom) {
      bloomCount = count;
    } else {
      pourCount = count;
    }
    // Fields may still be mounted during this rebuild. Only active rows are saved.
    notifyListeners();
  }

  BrewPourPhaseDraft phaseDraft(BrewPourKind kind, int number) =>
      _phases.putIfAbsent((kind, number), BrewPourPhaseDraft.new);

  bool get isValid {
    try {
      for (final phase in _phases.entries) {
        final (kind, number) = phase.key;
        final count = kind == BrewPourKind.bloom ? bloomCount : pourCount;
        if (number > (count ?? 0)) continue;
        final fields = phase.value;
        if (fields.water.text.trim().isNotEmpty &&
            parseNumber(fields.water.text) == null) {
          return false;
        }
        for (final field in [fields.duration, fields.rest]) {
          if (field.text.trim().isNotEmpty &&
              int.tryParse(field.text.trim()) == null) {
            return false;
          }
        }
      }
      value.validate();
      return true;
    } on FormatException {
      return false;
    }
  }

  List<Object?> get editState => [
    waterPlanUsed,
    if (waterPlanUsed) waterPlanBloomRatio,
    bloomCount,
    pourCount,
    for (final entry in _phases.entries.where((entry) => entry.value.hasValue))
      [
        entry.key.$1.name,
        entry.key.$2,
        entry.value.water.text,
        entry.value.waterFromPlan,
        entry.value.duration.text,
        entry.value.rest.text,
      ],
  ];

  BrewPours get value => BrewPours(
    bloomCount: bloomCount,
    pourCount: pourCount,
    phases: [
      for (final kind in BrewPourKind.values)
        for (
          var number = 1;
          number <=
              (kind == BrewPourKind.bloom ? bloomCount ?? 0 : pourCount ?? 0);
          number++
        )
          if (_phases[(kind, number)] case final draft?)
            if (draft.hasValue) draft.value(kind, number),
    ],
  );

  @override
  void dispose() {
    detailsController.dispose();
    for (final draft in _phases.values) {
      draft.dispose();
    }
    super.dispose();
  }
}

class BrewPourPhaseDraft {
  BrewPourPhaseDraft() {
    var previousText = water.text;
    water.addListener(() {
      if (water.text != previousText) waterFromPlan = false;
      previousText = water.text;
    });
  }

  bool waterFromPlan = false;
  final water = TextEditingController();
  final duration = TextEditingController();
  final rest = TextEditingController();

  bool get hasValue =>
      [water, duration, rest].any((c) => c.text.trim().isNotEmpty);

  void clear() {
    waterFromPlan = false;
    for (final controller in [water, duration, rest]) {
      controller.clear();
    }
  }

  void fill(BrewPourPhase phase) {
    water.text = fieldExact(phase.waterGrams);
    duration.text = phase.durationSeconds?.toString() ?? '';
    rest.text = phase.restSeconds?.toString() ?? '';
    waterFromPlan = phase.waterFromPlan;
  }

  BrewPourPhase value(BrewPourKind kind, int number) => BrewPourPhase(
    kind: kind,
    number: number,
    waterGrams: parseNumber(water.text),
    waterFromPlan: waterFromPlan,
    durationSeconds: int.tryParse(duration.text.trim()),
    restSeconds: int.tryParse(rest.text.trim()),
  );

  void dispose() {
    water.dispose();
    duration.dispose();
    rest.dispose();
  }
}
