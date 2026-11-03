import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/ui/core/error_report.dart';

/// Owns the recoverable draft and serialises writes before finalisation.
class CuppingModel extends ChangeNotifier {
  CuppingModel(
    this.repository,
    this.session,
    this.draft, {
    int Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    _wake();
  }

  final JournalRepository repository;
  CuppingSession session;
  final CuppingDraft draft;
  final int Function() clock;
  final feedback = const DeviceFeedback();
  List<Coffee> coffees = [];
  List<CoffeeLot> lots = [];
  List<FrozenPortion> portions = [];
  List<Grinder> grinders = [];
  List<WaterProfile> waters = [];
  final missingCups = <int>{};
  Timer? _timer;
  Timer? _autosave;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool _awake = false;
  bool busy = false;
  Object? error;
  int selected = 0;
  bool matrix = false;
  bool reviewingBlindScores = false;
  bool get completed => session.completedAtMs != null;
  int get elapsed => draft.elapsedAt(clock());
  bool get canStart =>
      draft.phase == CuppingPhase.setup &&
      draft.recipeValid &&
      (draft.blind || assignmentsValid);
  bool get scoresLocked => completed || (draft.blind && draft.revealed);
  bool get clockPaused => draft.pausedAtMs != null;
  bool get canFinish => draft.ready && assignmentsValid;
  bool get assignmentsValid => draft.cups.every(
    (c) =>
        coffees.any(
          (coffee) => coffee.id == c.coffeeId && coffee.archivedAtMs == null,
        ) &&
        (lots
                .where(
                  (l) => l.coffeeId == c.coffeeId && l.archivedAtMs == null,
                )
                .isEmpty ||
            c.lotId != null),
  );

  void setBlind(bool value) {
    if (draft.phase != CuppingPhase.setup) return;
    change(() {
      draft.blind = value;
      draft.revealed = false;
      for (final cup in draft.cups) {
        cup.coffeeId = null;
        cup.lotId = null;
        cup.frozenPortionId = null;
      }
    });
  }

  Future<bool> reveal() async {
    if (!draft.canReveal || busy || completed) return false;
    busy = true;
    _notify();
    try {
      await loadCatalogs();
      draft.revealed = true;
      draft.phase = CuppingPhase.review;
      if (!await flush()) {
        draft.revealed = false;
        draft.phase = CuppingPhase.tasting;
        return false;
      }
      return true;
    } catch (e, stack) {
      reportError(e, stack);
      error = e;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void reviewBlindScores(bool value) {
    reviewingBlindScores = value;
    _notify();
  }

  Future<void> loadCatalogs() async {
    final catalog = await repository.cuppingCatalog();
    coffees = catalog.coffees..sort((a, b) => a.name.compareTo(b.name));
    lots = catalog.lots;
    portions = catalog.portions;
    grinders = catalog.grinders..sort((a, b) => a.name.compareTo(b.name));
    waters = catalog.waters..sort((a, b) => a.name.compareTo(b.name));
    if (completed) {
      final links = await repository.cuppingCups(session.id);
      for (var i = 0; i < draft.cups.length; i++) {
        final link = links.where((c) => c.position == i).firstOrNull;
        final brew = link == null ? null : await repository.brew(link.brewId);
        if (brew == null) {
          missingCups.add(i);
          continue;
        }
        final cup = draft.cups[i];
        cup.coffeeId = brew.coffeeId;
        cup.commonGrinder = false;
        cup.grinderId = brew.grinderId;
        cup.grindSetting = brew.grindSetting ?? '';
        cup.commonWater = false;
        cup.waterProfileId = brew.waterProfileId;
        cup.rating = brew.rating;
        cup.scores = [
          brew.acidity,
          brew.sweetness,
          brew.bitterness,
          brew.body,
          brew.aftertaste,
        ];
        if (brew.rating != null) cup.notEvaluated[0] = false;
        for (var score = 0; score < 5; score++) {
          if (cup.scores[score] != null) cup.notEvaluated[score + 1] = false;
        }
        cup.notes = brew.notes ?? '';
      }
    }
    _notify();
  }

  void change(void Function() edit) {
    if (completed || busy) return;
    edit();
    error = null;
    _autosave?.cancel();
    _autosave = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(flush()),
    );
    _notify();
  }

  void select(int index) {
    selected = index;
    _notify();
  }

  void toggleView() {
    matrix = !matrix;
    _notify();
  }

  /// The clock continues from a timestamp across navigation and app restarts.
  void tick() {
    if (_disposed || completed || draft.phase == CuppingPhase.setup) return;
    if (clockPaused) return;
    if (draft.phase == CuppingPhase.infusion &&
        elapsed >= draft.crustSeconds &&
        !draft.crustAlerted) {
      change(() => draft.crustAlerted = true);
      if (draft.sound) unawaited(feedback.beep(long: true));
    } else if (draft.phase == CuppingPhase.cooling &&
        elapsed >= draft.tastingSeconds &&
        !draft.tastingAlerted) {
      change(() => draft.tastingAlerted = true);
      if (draft.sound) unawaited(feedback.beep(long: true));
    }
    _notify();
  }

  Future<bool> start() async {
    if (!canStart || busy) return false;
    busy = true;
    _notify();
    try {
      await repository.validateCuppingSetup(draft);
      draft.startedAtMs = clock();
      draft.timerStartedAtMs = draft.startedAtMs;
      draft.phase = CuppingPhase.infusion;
      if (!await flush()) {
        draft.startedAtMs = null;
        draft.timerStartedAtMs = null;
        draft.phase = CuppingPhase.setup;
        return false;
      }
      _wake();
      return true;
    } catch (e, stack) {
      reportError(e, stack);
      error = e;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void chooseCoffee(CuppingCupDraft cup, String? id) {
    if (draft.blind && !draft.revealed) return;
    change(() {
      cup.coffeeId = id;
      cup.lotId = null;
      cup.frozenPortionId = null;
      final active = lots
          .where((l) => l.coffeeId == id && l.archivedAtMs == null)
          .toList();
      final fresh = active
          .where(
            (l) =>
                l.remainingGrams == null ||
                l.remainingGrams! - (l.overdrawGrams ?? 0) + 0.000001 >=
                    draft.dose,
          )
          .firstOrNull;
      if (fresh != null) {
        cup.lotId = fresh.id;
        return;
      }
      final frozen = portions
          .where(
            (p) =>
                active.any((l) => l.id == p.lotId) &&
                p.remainingGrams + 0.000001 >= draft.dose,
          )
          .firstOrNull;
      cup.lotId = frozen?.lotId ?? active.firstOrNull?.id;
      cup.frozenPortionId = frozen?.id;
    });
  }

  void breakCrust() => change(() {
    draft.brokenAtMs = clock();
    draft.phase = CuppingPhase.cooling;
  });
  void taste() => change(() {
    draft.tastingAtMs = clock();
    draft.phase = CuppingPhase.tasting;
  });

  void toggleClock() => change(() {
    if (draft.pausedAtMs case final paused?) {
      draft.pausedTotalMs += (clock() - paused).clamp(0, 1 << 30);
      draft.pausedAtMs = null;
    } else {
      draft.pausedAtMs = clock();
    }
  });

  void resetClock() => change(() {
    final now = clock();
    final base = draft.phase == CuppingPhase.cooling ? draft.crustSeconds : 0;
    draft.timerStartedAtMs = now - base * 1000;
    draft.pausedAtMs = null;
    draft.pausedTotalMs = 0;
    if (draft.phase == CuppingPhase.infusion) draft.crustAlerted = false;
    if (draft.phase == CuppingPhase.cooling) draft.tastingAlerted = false;
  });

  void setTarget({required bool infusion, required int seconds}) => change(() {
    if (infusion) {
      draft.crustSeconds = seconds;
    } else {
      draft.tastingSeconds = seconds;
    }
    draft.crustAlerted = false;
    draft.tastingAlerted = false;
  });

  Future<bool> flush() async {
    _autosave?.cancel();
    if (completed) return true;
    final snapshot = CuppingDraft.fromJson(draft.toJson());
    var success = true;
    _writes = _writes.then((_) async {
      try {
        await repository.saveCuppingDraft(session.id, snapshot);
        error = null;
      } catch (e, stack) {
        reportError(e, stack);
        error = e;
        success = false;
      }
    });
    await _writes;
    _notify();
    return success;
  }

  Future<bool> finish() async {
    if (busy || completed || !canFinish) return false;
    busy = true;
    _notify();
    try {
      if (!await flush()) return false;
      await repository.finishCupping(session.id, draft);
      session = (await repository.cuppingSession(session.id))!;
      _timer?.cancel();
      if (_awake) {
        _awake = false;
        await feedback.keepScreenOn(false);
      }
      return true;
    } catch (e, stack) {
      reportError(e, stack);
      error = e;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _wake() {
    if (!completed && draft.phase != CuppingPhase.setup && !_awake) {
      _awake = true;
      unawaited(feedback.keepScreenOn(true));
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autosave?.cancel();
    _disposed = true;
    if (_awake) unawaited(feedback.keepScreenOn(false));
    super.dispose();
  }
}
