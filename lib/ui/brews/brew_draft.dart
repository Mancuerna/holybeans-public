import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brix.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

/// The brew form's text fields. They start from the brew being edited, or
/// the one being repeated (recipe and notes), and can later be filled from the
/// method memory or from a machine's shot.
class BrewDraft {
  BrewDraft({
    Brew? existing,
    Brew? seed,
    bool repeat = false,
    double? initialDoseGrams,
  }) {
    final repeated = repeat ? seed : null;
    pours = BrewPoursDraft(existing: existing, repeated: repeated);
    final preGround = existing?.isPreGround ?? seed?.isPreGround ?? false;
    grindSetting = TextEditingController(
      text: preGround ? null : existing?.grindSetting ?? repeated?.grindSetting,
    );
    dose = TextEditingController(
      text: _number(
        existing?.doseGrams ?? repeated?.doseGrams,
      ).ifEmpty(initialDoseGrams == null ? '' : fieldNumber(initialDoseGrams)),
    );
    water = TextEditingController(
      text: _number(existing?.waterGrams ?? repeated?.waterGrams),
    );
    temperature = TextEditingController(
      text: _number(existing?.temperatureC ?? repeated?.temperatureC),
    );
    beverage = TextEditingController(text: _number(existing?.beverageGrams));
    final seconds = existing?.timeSeconds;
    durationMinutes = TextEditingController(
      text: seconds == null ? '' : '${seconds ~/ 60}',
    );
    durationSeconds = TextEditingController(
      text: seconds == null ? '' : _twoDigits(seconds % 60),
    );
    brixMode = existing?.brix != null;
    brix = TextEditingController(text: _number(existing?.brix));
    brixFactor = TextEditingController(
      text: _number(existing?.brixFactor ?? 0.85),
    );
    tds = TextEditingController(text: _number(existing?.tdsPercent));
    grindRpm = TextEditingController(
      text: _integer(existing?.grindRpm ?? repeated?.grindRpm),
    );

    feederRpm = TextEditingController(
      text: _integer(existing?.feederRpm ?? repeated?.feederRpm),
    );
    pressure = TextEditingController(
      text: _number(existing?.pressureBar ?? repeated?.pressureBar),
    );
    preinfusion = TextEditingController(
      text: _integer(
        existing?.preinfusionSeconds ?? repeated?.preinfusionSeconds,
      ),
    );
    bloom = TextEditingController(
      text: _integer(existing?.bloomSeconds ?? repeated?.bloomSeconds),
    );
    firstDrip = TextEditingController(
      text: _integer(existing?.firstDripSeconds),
    );
    notes = TextEditingController(text: existing?.notes ?? repeated?.notes);
    profile = TextEditingController(
      text: existing?.profileName ?? repeated?.profileName,
    );
  }

  late final BrewPoursDraft pours;
  late final TextEditingController grindSetting;
  late final TextEditingController dose;
  late final TextEditingController water;
  late final TextEditingController temperature;
  late final TextEditingController beverage;
  late final TextEditingController durationMinutes;
  late final TextEditingController durationSeconds;
  late bool brixMode;
  late final TextEditingController brix;
  late final TextEditingController brixFactor;
  double? get effectiveTds => brixMode
      ? brixToTds(parseNumber(brix.text), parseNumber(brixFactor.text))
      : parseNumber(tds.text);
  late final TextEditingController tds;
  late final TextEditingController grindRpm;
  late final TextEditingController feederRpm;
  late final TextEditingController pressure;
  late final TextEditingController preinfusion;
  late final TextEditingController bloom;

  /// Espresso: seconds until the first drop, a result like the time.
  late final TextEditingController firstDrip;

  /// The full jug on the scale; only used to work out [beverage].
  final jugTotal = TextEditingController();
  late final TextEditingController notes;
  late final TextEditingController profile;

  /// Values last written by the method memory, so a later method change can
  /// replace them without touching anything the user typed.
  final Map<TextEditingController, String> _memoryValues = {};

  static String _number(double? value) =>
      value == null ? '' : fieldExact(value);
  static String _integer(int? value) => value?.toString() ?? '';
  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  List<TextEditingController> get fields => [
    grindSetting,
    dose,
    water,
    temperature,
    beverage,
    durationMinutes,
    durationSeconds,
    tds,
    brix,
    brixFactor,
    grindRpm,
    feederRpm,
    pressure,
    preinfusion,
    bloom,
    firstDrip,
    jugTotal,
    notes,
    profile,
  ];

  /// The extraction time typed or timed, in seconds.
  int? get timeSeconds => durationSecondsOf(durationMinutes, durationSeconds);

  bool get hasValidPourDetails =>
      pours.isValid &&
      (pours.bloomCount == 0 ||
          bloom.text.trim().isEmpty ||
          (int.tryParse(bloom.text.trim()) ?? 0) > 0);

  /// Copies the recipe of [brew], the last one with the chosen method:
  /// grind, dose, water (not for [espresso], where the yield is a result),
  /// temperature, pressure, pre-infusion, bloom and profile. Results (yield,
  /// time, TDS) and notes stay as they are, and so does any field the user
  /// has typed in.
  void applyMemory(Brew brew, {required bool espresso}) {
    void fill(TextEditingController field, String value) {
      final current = field.text.trim();
      if (current.isNotEmpty && current != _memoryValues[field]) return;
      field.text = value;
      _memoryValues[field] = value;
    }

    String number(double? value) => value == null ? '' : fieldNumber(value);

    fill(grindSetting, brew.isPreGround ? '' : brew.grindSetting ?? '');
    fill(grindRpm, _integer(brew.grindRpm));
    fill(feederRpm, _integer(brew.feederRpm));
    fill(dose, number(brew.doseGrams));
    if (!espresso) fill(water, number(brew.waterGrams));
    fill(temperature, number(brew.temperatureC));
    fill(pressure, number(brew.pressureBar));
    fill(preinfusion, _integer(brew.preinfusionSeconds));
    fill(bloom, _integer(brew.bloomSeconds));
    fill(profile, brew.profileName ?? '');
    pours.applyMemory(
      blooms: espresso ? null : brew.bloomCount,
      pours: espresso ? null : brew.pourCount,
    );
  }

  /// Applies recorded measurements and optional notes from Gaggimate.
  void applyGaggimateShot(GaggimateShot shot) {
    String number(double? value) => value == null ? '' : fieldNumber(value);
    durationMinutes.text = '${shot.timeSeconds ~/ 60}';
    durationSeconds.text = _twoDigits(shot.timeSeconds % 60);
    beverage.text = number(shot.yieldGrams);
    temperature.text = number(shot.temperatureC);
    pressure.text = number(shot.peakPressureBar);
    firstDrip.text = _integer(shot.firstDripSeconds);
    preinfusion.text = _integer(shot.preinfusionSeconds);
    profile.text = shot.profileName;
    if (shot.doseGrams case final grams?) dose.text = fieldNumber(grams);
    if (shot.grindSetting case final grind?) grindSetting.text = grind;
    if (shot.notes case final note?) notes.text = note;
  }

  /// Applies Meticulous measurements, leaving dose and grind unchanged.
  void applyShot(MeticulousShot shot) {
    if (shot.timeSeconds case final seconds?) {
      durationMinutes.text = '${seconds ~/ 60}';
      durationSeconds.text = _twoDigits(seconds % 60);
    }
    if (shot.yieldGrams case final grams?) beverage.text = fieldNumber(grams);
    if (shot.temperatureC case final celsius?) {
      temperature.text = fieldNumber(celsius);
    }
    if (shot.peakPressureBar case final bar?) {
      pressure.text = fieldNumber(bar);
    }
    preinfusion.text = _integer(shot.preinfusionSeconds);
    firstDrip.text = _integer(shot.firstDripSeconds);
    profile.text = shot.profileName;
  }

  /// Fills what the Meticulous measured in a free [pour]: dose, water,
  /// beverage, temperature and time replace the recipe; its pours fill the
  /// blooms and pours when none are written, keeping a bloom count given.
  void applyFreePour(MeticulousFreePour pour) {
    void put(TextEditingController field, double? value) {
      if (value != null) field.text = fieldNumber(value);
    }

    put(dose, pour.doseGrams);
    put(water, pour.waterGrams);
    put(beverage, pour.beverageGrams);
    put(temperature, pour.temperatureC);
    if (pour.timeSeconds case final seconds?) {
      durationMinutes.text = '${seconds ~/ 60}';
      durationSeconds.text = _twoDigits(seconds % 60);
    }
    if (!pours.takesCurve) return;
    if (brewPoursOf(
          pour.pours,
          doseGrams: pour.doseGrams,
          bloomCount: pours.bloomCount,
          pourCount: pours.curvePourCount,
        )
        case final found?) {
      pours.fillFromCurve(found, bloomTotal: bloom);
    }
  }

  /// Fills what a guided pour decided: dose, water, bloom and the brew
  /// time it took.
  /// [pouredGrams], when a scale measured it, replaces the planned water.
  void applyPour(
    PourPlan plan,
    int totalSeconds, {
    double? pouredGrams,
    ShotCurve? curve,
  }) {
    dose.text = fieldNumber(plan.doseGrams);
    water.text = fieldNumber(
      ((pouredGrams ?? plan.totalWaterGrams) * 10).round() / 10,
    );
    final measured = curve == null
        ? null
        : brewPoursFromCurve(
            curve,
            doseGrams: plan.doseGrams,
            bloomCount: plan.blooms.length,
          );
    if (measured != null) {
      pours.fillFromCurve(measured, bloomTotal: bloom, replaceBloomTime: true);
    } else {
      pours.applyPlan(blooms: plan.blooms.length, pours: plan.pours);
      bloom.text = plan.bloomSeconds > 0 ? '${plan.bloomSeconds}' : '';
    }
    if (totalSeconds > 0) {
      durationMinutes.text = '${totalSeconds ~/ 60}';
      durationSeconds.text = _twoDigits(totalSeconds % 60);
    }
  }

  /// Writes a scale's [grams] into [field], to a tenth of a gram.
  void fillWeight(TextEditingController field, double grams) =>
      field.text = fieldNumber((grams * 10).round() / 10);

  /// Sets the beverage to the weight with the jug minus [emptyGrams], when
  /// both are known and the difference is positive.
  void applyTare(double? emptyGrams) {
    final total = parseNumber(jugTotal.text);
    if (total == null || emptyGrams == null) return;
    final net = total - emptyGrams;
    if (net <= 0) return;
    final text = fieldNumber((net * 10).round() / 10);
    if (beverage.text != text) beverage.text = text;
  }

  /// Shows the full weight of a saved brew's jug, from its beverage.
  void fillJugTotal(double emptyGrams) {
    final net = parseNumber(beverage.text);
    if (jugTotal.text.trim().isNotEmpty || net == null) return;
    jugTotal.text = fieldNumber(net + emptyGrams);
  }

  void dispose() {
    pours.dispose();
    for (final controller in fields) {
      controller.dispose();
    }
  }
}
