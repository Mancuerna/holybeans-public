import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

/// The paired Bluetooth devices during one brew form, kept in step with its
/// timer: the scale (which can also start and stop it) and the pressure
/// sensor. Stopping a filter recording replaces its planned water with the
/// measured water. Espresso pressure is replaced on Stop; refractometer results replace
/// the TDS because each is a measurement the user just asked for.
class BrewDevices {
  BrewDevices({
    required this.draft,
    required this.timer,
    required bool Function() isEspresso,
    Scale? scale,
    PressureSensor? pressureSensor,
    Refractometer? refractometer,
    VoidCallback? onMeasurement,
  }) : _isEspresso = isEspresso,
       refractometer = refractometer?.name == null ? null : refractometer,
       scale = scale?.name == null ? null : BrewScaleSession(scale!),
       pressure = pressureSensor?.name == null
           ? null
           : BrewPressureSession(pressureSensor!) {
    // Waits only for a scale that is connecting, so its curve is not lost;
    // with the scale off, flat or out of range the timer runs on its own.
    timer.allowStart = () =>
        !(this.scale?.resetting ?? false) &&
        !(this.scale?.weighingDose ?? false) &&
        switch (this.scale?.scale.status) {
          DeviceStatus.connecting || DeviceStatus.searching => false,
          _ => true,
        };
    timer.restartOnStart = () => this.scale?.restartsOnNextStart ?? false;
    this.scale
      ?..requestStart = (() => timer.running ? null : timer.toggle())
      ..requestStop = (atSeconds) {
        timer.stop();
        if (atSeconds != null) timer.settle(atSeconds);
      }
      ..isEspresso = isEspresso
      ..doseGrams = (() => parseNumber(draft.dose.text))
      ..onFirstDrip = _fillFirstDrip;
    _doses = this.scale?.scale.doses.listen((grams) {
      if (this.scale?.weighingDose == true || !grams.isFinite || grams <= 0) {
        return;
      }
      draft.dose.text = fieldNumber(grams, decimals: 1);
      onMeasurement?.call();
    });
    _results = this.refractometer?.messages.listen((message) {
      switch (message) {
        case R2Measuring():
          measureProblem.value = null;
        // Below zero is water or an empty prism, not a brew.
        case R2Result(:final tdsPercent) when tdsPercent < 0:
          measureProblem.value = message;
        case R2Result(:final tdsPercent):
          measureProblem.value = null;
          draft.brixMode = false;
          draft.tds.text = fieldNumber(tdsPercent, decimals: 2);
          onMeasurement?.call();
        case R2Failed():
          measureProblem.value = message;
        case R2TestCount():
          break;
      }
    });
  }

  final BrewDraft draft;
  final BrewTimer timer;
  final bool Function() _isEspresso;

  /// The scale during this brew; null without a paired one.
  final BrewScaleSession? scale;

  /// The pressure sensor during this brew; null without a paired one.
  final BrewPressureSession? pressure;

  /// The paired refractometer, whose results fill the TDS, whether asked
  /// for from the form or with its own button.
  final Refractometer? refractometer;
  StreamSubscription<R2Message>? _results;
  StreamSubscription<double>? _doses;

  /// What went wrong with the refractometer's last measurement: a failure
  /// (no sample, out of range) or a result below zero; null when it went
  /// well.
  final measureProblem = ValueNotifier<R2Message?>(null);

  double? _filterWaterTarget;
  bool _filterTargetCaptured = false;

  /// The planned water remains available after Stop writes the measured water.
  double? get filterWaterTarget => _filterTargetCaptured
      ? _filterWaterTarget
      : parseNumber(draft.water.text);

  void timerStarted(int fromSeconds) {
    if (scale?.restartsOnNextStart ?? false) pressure?.timerReset();
    if (!_isEspresso() && !_filterTargetCaptured && scale != null) {
      _filterWaterTarget = parseNumber(draft.water.text);
      _filterTargetCaptured = true;
    }
    scale?.timerStarted(fromSeconds);
    pressure?.timerStarted(fromSeconds);
  }

  /// Stop records measured filter water, including over a ratio shortcut.
  /// Espresso replaces pressure with the sensor peak; typed yield stays intact.
  void timerStopped() {
    scale?.timerStopped();
    pressure?.timerStopped();
    // A discarded attempt must not fill the result of the next one.
    if (scale?.restartsOnNextStart ?? false) return;
    if (!_isEspresso()) {
      if (recordedWaterGrams(scale?.curve) case final grams?
          when grams >= 0.5) {
        draft.water.text = fieldNumber(grams, decimals: 1);
      }
      return;
    }
    if (pressure?.peakBar case final peak? when peak > 0) {
      draft.pressure.text = fieldNumber(peak, decimals: 1);
    }
    // Accepted load, keeping the beverage when the cup is lifted off.
    if (scale?.beverageGrams case final grams?
        when draft.beverage.text.trim().isEmpty && grams >= 0.5) {
      draft.beverage.text = fieldNumber(grams, decimals: 1);
    }
  }

  void timerReset() {
    _filterTargetCaptured = false;
    _filterWaterTarget = null;
    scale?.timerReset();
    pressure?.timerReset();
  }

  void _fillFirstDrip(int seconds) {
    if (draft.firstDrip.text.trim().isEmpty) {
      draft.firstDrip.text = '$seconds';
    }
  }

  /// The curve to save: the scale's, with the sensor's pressure for an
  /// espresso (the sensor sits on the espresso machine).
  ShotCurve? get curve => switch (scale?.curve) {
    final curve? when _isEspresso() => pressure?.withPressure(curve) ?? curve,
    final curve => curve,
  };

  void dispose() {
    unawaited(_doses?.cancel());
    unawaited(_results?.cancel());
    measureProblem.dispose();
    scale?.dispose();
    pressure?.dispose();
  }
}
