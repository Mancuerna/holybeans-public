import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/freeze_plan.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_catalogs.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_form_persistence.dart';
import 'package:holybeans/ui/brews/brew_form_recipes.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/brew_timer_notice.dart';
import 'package:holybeans/ui/brews/brew_tools_model.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/photos_draft.dart';

part 'brew_form_catalogs.dart';
part 'brew_form_loading.dart';

/// State and logic of the brew form: what is chosen (coffee, lot, method,
/// grinder, water, tools), the catalogs to choose from, the help shown
/// (last brew, method memory) and saving. The form only draws it.
///
/// The view reads fields; changes through methods notify listeners.
class BrewFormModel extends ChangeNotifier {
  BrewFormModel({
    required this.services,
    required this.coffees,
    this.existing,
    this.seed,
    this.repeat = false,
    String? initialCoffeeId,
    String? initialLotId,
    double? initialDoseGrams,
    this.initialFrozenSource,
    String? initialMethodId,
    List<String> savedPhotos = const [],
  }) : draft = BrewDraft(
         existing: existing,
         seed: seed,
         repeat: repeat,
         initialDoseGrams: initialDoseGrams,
       ),
       photoDraft = PhotosDraft(services.photos, savedPhotos),
       rating = existing?.rating,
       brewedAt = existing == null
           ? DateTime.now()
           : DateTime.fromMillisecondsSinceEpoch(existing.brewedAtMs) {
    draft.pours.addListener(_notify);
    photoDraft.addListener(_notify);
    timer = BrewTimer(
      minutes: draft.durationMinutes,
      seconds: draft.durationSeconds,
      onStart: (fromSeconds) {
        devices.timerStarted(fromSeconds);
        _notice.started(fromSeconds);
        _notify();
      },
      onStop: () {
        devices.timerStopped();
        _notice.ended();
        if (!(devices.scale?.restartsOnNextStart ?? false)) {
          fillPoursFromCurve(devices.curve);
        }
        _notify();
      },
      onReset: () {
        devices.timerReset();
        _notice.ended();
        _notify();
      },
    );
    devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => isEspresso,
      scale: services.scale,
      pressureSensor: services.pressureSensor,
      refractometer: services.refractometer,
      onMeasurement: _notify,
    );
    devices.scale?.addListener(_notify);
    _start(
      initialCoffeeId: initialCoffeeId,
      initialLotId: initialLotId,
      initialMethodId: initialMethodId,
    );
  }

  /// The espresso yield aimed at: the ratio of the brew edited, repeated or
  /// remembered, 1:2 without one.
  double espressoTargetRatio = 2;
  bool _targetTouched = false;

  void _aimAt(Brew? brew) {
    if (_targetTouched || brew == null) return;
    if (espressoTargetRatioOf(
          doseGrams: brew.doseGrams,
          beverageGrams: brew.beverageGrams,
        )
        case final ratio?) {
      espressoTargetRatio = ratio;
    }
  }

  double? get espressoTargetGrams => brewRatioTargetGrams(
    doseGrams: parseNumber(draft.dose.text),
    ratio: espressoTargetRatio,
  );

  void setEspressoTargetRatio(double ratio) {
    _targetTouched = true;
    espressoTargetRatio = ratio;
    _notify();
  }

  static const preGroundChoice = '__holybeans_pre_ground__';

  final AppServices services;
  late final catalogs = BrewCatalogs(
    repository: repository,
    onMethods: _methodsChanged,
    onMethodsReady: () {
      if (methodId case final method? when savedToolsLoaded) {
        _loadTools(method, preferredIds: selectedToolIds);
      }
    },
    onGrinders: _grindersChanged,
    onWaterProfiles: _waterProfilesChanged,
    onRecipients: _recipientsChanged,
    onLots: (rows, preferred) {
      lotId = rows.any((lot) => lot.id == preferred)
          ? preferred
          : rows.firstOrNull?.id;
    },
  )..addListener(_notify);
  late final toolSelection = BrewToolsModel(
    repository: repository,
    methodId: () => methodId,
    existing: existing,
    selectedBrew: existing ?? (repeat ? seed : null),
  )..addListener(_notify);

  JournalRepository get repository => services.repository;
  BrewParameterSettings get settings => services.parameterSettings;
  final List<Coffee> coffees;

  /// The brew being edited.
  final Brew? existing;

  /// The brew being repeated, or the one the form starts from.
  final Brew? seed;
  final bool repeat;

  final BrewDraft draft;
  late final BrewTimer timer;
  final PhotosDraft photoDraft;

  /// The paired scale and pressure sensor during this brew.
  late final BrewDevices devices;

  BrewScaleSession? get scaleSession => devices.scale;
  BrewPressureSession? get pressureSession => devices.pressure;

  bool get isNew => existing == null;

  /// Whether the method memory and the last brew help apply: only to a
  /// brand-new brew.
  bool get _fresh => existing == null && !repeat;

  DateTime brewedAt;
  double? rating;

  String? coffeeId;
  late final _notice = BrewTimerNotice(
    describe: () => (
      title:
          coffees.where((coffee) => coffee.id == coffeeId).firstOrNull?.name ??
          methodName,
      text: methodName,
    ),
  );
  String? lotId;
  List<CoffeeLot> get lots => catalogs.lots;
  bool get loadingLots => catalogs.loadingLots;

  String? methodId;
  List<BrewMethod> get methods => catalogs.methods;
  bool get loadingMethods => catalogs.loadingMethods;
  List<String> get profileSuggestions =>
      catalogs.profiles?.forMethod(methodId) ?? const [];

  String? grinderId;
  bool isPreGround = false;

  /// Whether the user picked a grinder, so memory no longer replaces it.
  bool grinderTouched = false;
  List<Grinder> get grinders => catalogs.grinders;
  bool get loadingGrinders => catalogs.loadingGrinders;

  String? waterProfileId;
  List<WaterProfile> get waterProfiles => catalogs.waterProfiles;
  bool get loadingWaterProfiles => catalogs.loadingWaterProfiles;
  bool _recipientChosen = false;
  Recipient? recipient;
  List<Recipient> get recipients => catalogs.recipients;
  bool get loadingRecipients => catalogs.loadingRecipients;

  Set<String> get selectedToolIds => toolSelection.selectedIds;
  List<MethodTool> get tools => toolSelection.tools;
  Map<String, int> get toolUseCounts => toolSelection.useCounts;
  bool get loadingTools => toolSelection.loading;
  bool get savedToolsLoaded => toolSelection.savedLoaded;

  Set<BrewParameter> hiddenFields = const {};

  /// Method whose last brew filled the recipe, for the hint.
  String? get memoryMethodName => _recipes.memory?.brew.methodName;

  /// Whether that brew was the favourite of the coffee and method.
  bool get memoryFromFavorite => _recipes.memory?.favorite ?? false;

  /// The favourite brew of the chosen coffee and method, the base the help
  /// card shows instead of the last one.
  Brew? get favorite => _recipes.references?.favorite;

  /// Last rated brew of the chosen coffee with the chosen method (or the
  /// last one when none is rated), shown with the advice for the next one.
  Brew? get dialIn => _recipes.references?.last;
  bool get dialInRated => _recipes.references?.lastRated ?? false;

  /// Latest brew of the chosen coffee with the chosen method, rated or not:
  /// its notes are often written for the next brew.
  Brew? get newestBrew => _recipes.references?.newest;

  /// Shot picked from the method's Meticulous, or free pour from its scale
  /// in a filter brew; saved with the brew.
  MeticulousShot? importedShot;
  GaggimateShot? importedGaggimateShot;
  MeticulousFreePour? importedFreePour;
  bool saving = false;
  late final _recipes = BrewFormRecipes(
    loadMemory: repository.methodMemory,
    loadReferences: repository.dialInFor,
    notify: _notify,
  );
  bool get loadingMemory => _recipes.loading;
  bool _waterTouched = false;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool get hasLoadError => catalogs.hasError || toolSelection.hasError;
  bool _retrying = false;
  final FrozenBrewSource? initialFrozenSource;

  FrozenBrewSource? get pendingFrozenSource =>
      existing == null && initialFrozenSource?.lotId == lotId
      ? initialFrozenSource
      : null;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _start({
    String? initialCoffeeId,
    String? initialLotId,
    String? initialMethodId,
  }) {
    final recorded = existing ?? (repeat ? seed : null);
    _aimAt(existing ?? seed);
    _recipientChosen = existing != null || recorded?.recipientId != null;
    if (recorded?.recipientId != null && recorded?.recipientGrams != null) {
      recipient = Recipient(
        id: recorded!.recipientId!,
        name: recorded.recipientName!,
        emptyGrams: recorded.recipientGrams!,
        isPortafilter: recorded.recipientIsPortafilter,
      );
      if (existing != null && !recipient!.isPortafilter) {
        draft.fillJugTotal(recipient!.emptyGrams);
      }
    }
    methodId = existing?.methodId ?? initialMethodId ?? seed?.methodId;
    waterProfileId =
        existing?.waterProfileId ?? (repeat ? seed?.waterProfileId : null);
    isPreGround = existing?.isPreGround ?? seed?.isPreGround ?? false;
    grinderId = isPreGround ? null : existing?.grinderId ?? seed?.grinderId;
    final preferred = existing?.coffeeId ?? seed?.coffeeId ?? initialCoffeeId;
    coffeeId = coffees.any((coffee) => coffee.id == preferred)
        ? preferred
        : repeat
        ? null
        : coffees.firstOrNull?.id;
    catalogs.prepareLots(loading: coffeeId != null);

    _subscriptions.add(
      settings.watchHidden().listen((hidden) {
        hiddenFields = hidden;
        _notify();
      }),
    );
    draft.jugTotal.addListener(() => draft.applyTare(jugGrams));

    if (_fresh && methodId != null) {
      unawaited(_applyMethodMemory(methodId!));
    }
    if (isNew) unawaited(_loadDialIn());
    unawaited(_loadSavedTools());
    _watchCatalogs();
    unawaited(_loadProfileSuggestions());
    if (coffeeId != null) {
      _loadLots(
        coffeeId!,
        preferred: existing?.lotId ?? seed?.lotId ?? initialLotId,
      );
    }
  }

  Future<void> _loadDialIn() =>
      _recipes.loadReferences(coffeeId: coffeeId, methodId: methodId);

  /// Prefills a new brew from the favourite of the chosen coffee with
  /// [selectedMethodId], or else what was last used with the method (with
  /// the coffee if possible): grinder, recipe, tools and water. Results stay
  /// empty, and fields the user typed in are kept.
  Future<void> _applyMethodMemory(String selectedMethodId) => _recipes.load(
    coffeeId: coffeeId,
    methodId: selectedMethodId,
    apply: (memory) async {
      if (memory == null) {
        await _loadTools(selectedMethodId);
        return;
      }
      final (:brew, favorite: _, toolIds: lastTools) = memory;
      _aimAt(brew);
      if (!grinderTouched) {
        isPreGround = brew.isPreGround;
        grinderId = brew.isPreGround ? null : brew.grinderId;
      }
      draft.applyMemory(
        brew,
        espresso: isEspressoMethod(
          category: methods
              .where((row) => row.id == selectedMethodId)
              .firstOrNull
              ?.category,
          methodName: brew.methodName,
        ),
      );
      if (!_waterTouched &&
          waterProfileId == null &&
          waterProfiles.any(
            (row) => row.id == brew.waterProfileId && row.archivedAtMs == null,
          )) {
        waterProfileId = brew.waterProfileId;
      }
      _notify();
      await _loadTools(
        selectedMethodId,
        preferredIds: toolSelection.touched
            ? selectedToolIds.toList()
            : lastTools,
      );
    },
  );

  BrewMethod? get selectedMethod =>
      methods.where((row) => row.id == methodId).firstOrNull;

  /// Name of the chosen method, or the one saved with the brew.
  String get methodName =>
      selectedMethod?.name ?? existing?.methodName ?? seed?.methodName ?? '';

  bool get isEspresso => isEspressoMethod(
    category: selectedMethod?.category,
    methodName: methodName,
  );

  /// The selected espresso method when it is connected to a Meticulous.
  BrewMethod? get meticulousMethod => switch (selectedMethod) {
    final method?
        when isEspresso &&
            method.machine == 'meticulous' &&
            (method.machineAddress?.trim().isNotEmpty ?? false) =>
      method,
    _ => null,
  };

  BrewMethod? get gaggimateMethod => switch (selectedMethod) {
    final method?
        when isEspresso &&
            method.machine == 'gaggimate' &&
            (method.machineAddress?.trim().isNotEmpty ?? false) =>
      method,
    _ => null,
  };

  /// Where a filter brew reads a free pour from, if anywhere.
  String? get freePourAddress => isEspresso || selectedMethod == null
      ? null
      : freePourMachineAddress(methods);

  /// The plan to open the pour assistant with: the method's last recipe at
  /// the dose typed, or a common one at the ratio typed.
  PourPlan pourPlanToStart() => PourPlan.toStart(
    saved: selectedMethod?.pourPlanJson,
    doseGrams: parseNumber(draft.dose.text) ?? 15,
    waterGrams: parseNumber(draft.water.text),
    brewPours: draft.pours.isValid ? draft.pours.value : null,
    bloomSeconds: int.tryParse(draft.bloom.text),
  );

  /// Fills the brew from a finished pour and has the method remember the
  /// recipe for next time. With a scale, the water poured and its curve
  /// come from it.
  Future<void> applyPour(
    PourPlan plan,
    int totalSeconds, {
    ShotCurve? curve,
    double? pouredGrams,
  }) async {
    timer.stop();
    draft.applyPour(plan, totalSeconds, pouredGrams: pouredGrams, curve: curve);
    scaleSession?.pourFinished(curve);
    _notify();
    if (methodId case final id?) {
      try {
        await repository.setMethodPourPlan(id, plan);
      } catch (error, stack) {
        reportError(error, stack);
        // The brew is filled in either way.
      }
    }
  }

  /// When a filter brew's timer stops with a scale [curve] and no bloom or
  /// pour details, fills them while respecting counts chosen in this form.
  /// The curve's pour count wins over one copied from a repeated brew, as
  /// it is what was poured. The form offers
  /// to undo it.
  void fillPoursFromCurve(ShotCurve? curve) {
    final pours = draft.pours;
    if (isEspresso || !pours.takesCurve || curve == null) return;
    if (brewPoursFromCurve(
          curve,
          doseGrams: parseNumber(draft.dose.text),
          bloomCount: pours.bloomCount,
          pourCount: pours.curvePourCount,
        )
        case final found?) {
      pours.fillFromCurve(found, bloomTotal: draft.bloom, expandDetails: false);
    }
  }

  /// Empty weight of the chosen filter method's jug, if it has one.
  double? get jugGrams => isEspresso ? null : recipient?.emptyGrams;

  void selectRecipient(Recipient? value) {
    _recipientChosen = true;
    recipient = value;
    if (value == null) draft.jugTotal.clear();
    draft.applyTare(jugGrams);
    _notify();
  }

  void _defaultRecipient() {
    if (_recipientChosen || loadingRecipients) return;
    recipient = recipients
        .where(
          (r) =>
              r.id == selectedMethod?.defaultRecipientId &&
              r.isPortafilter == isEspresso &&
              r.archivedAtMs == null,
        )
        .firstOrNull;
  }

  void setBrixMode(bool value) {
    draft.brixMode = value;
    _notify();
  }

  bool get selectedGrinderHasFeederRpm =>
      !isPreGround &&
      grinders.any((g) => g.id == grinderId && g.hasAdjustableFeederRpm);
  bool get selectedGrinderHasRpm =>
      !isPreGround &&
      grinders.any((row) => row.id == grinderId && row.hasAdjustableRpm);

  /// Hidden fields keep their values from imports, devices and Repeat.
  bool shows(BrewParameter parameter) => !hiddenFields.contains(parameter);

  bool get timerAtWaterPlan {
    if (isEspresso ||
        (scaleSession?.scale.connected ?? false) ||
        !shows(BrewParameter.bloomCount) ||
        !shows(BrewParameter.pourCount) ||
        !draft.pours.waterPlanExpanded) {
      return false;
    }
    final plan = draft.pours.waterPlan(
      dose: parseNumber(draft.dose.text),
      water: devices.filterWaterTarget,
    );
    return plan != null && plan.problem == null;
  }

  /// Whether the form is still loading or saving, so it cannot be saved. A
  /// missing method is not: Save then says what is missing.
  bool get busy =>
      saving ||
      hasLoadError ||
      _retrying ||
      photoDraft.locked ||
      loadingRecipients ||
      photoDraft.picking ||
      loadingMemory ||
      loadingLots ||
      loadingMethods ||
      loadingGrinders ||
      loadingWaterProfiles ||
      loadingTools ||
      !savedToolsLoaded;

  void setBrewedAt(DateTime value) {
    brewedAt = value;
    _notify();
  }

  void setRating(double? value) {
    rating = value;
    _notify();
  }

  void setPhotos(List<String> names) {
    photoDraft.set(names);
    _notify();
  }

  void selectCoffee(String id) {
    coffeeId = id;
    toolSelection.cancelPending();
    lotId = null;
    catalogs.prepareLots(clear: true);
    catalogs.publish();
    toolSelection.publish();
    _loadLots(id);
    if (isNew) {
      _loadDialIn();
      // The recipe last used with this coffee beats the method's.
      if (_fresh && methodId != null) {
        unawaited(_applyMethodMemory(methodId!));
      }
    }
  }

  void selectLot(String? id) {
    lotId = id;
    _notify();
  }

  Future<void> selectMethod(String? id) async {
    if (id == null || id == methodId) return;
    importedGaggimateShot = null;
    importedShot = null;
    importedFreePour = null;
    methodId = id;
    _recipientChosen = false;
    _defaultRecipient();
    draft.jugTotal.clear();
    toolSelection.resetForMethod();
    draft.applyTare(jugGrams);
    toolSelection.publish();
    if (isNew) unawaited(_loadDialIn());
    if (_fresh) {
      await _applyMethodMemory(id);
    } else {
      await _loadTools(id);
    }
  }

  /// Picks a grinder by id, '' for none or [preGroundChoice].
  void selectGrinder(String choice) {
    isPreGround = choice == preGroundChoice;
    grinderId = choice.isEmpty || isPreGround ? null : choice;
    if (isPreGround) draft.grindSetting.clear();
    grinderTouched = true;
    _notify();
  }

  void selectWaterProfile(String? id) {
    _waterTouched = true;
    waterProfileId = id == null || id.isEmpty ? null : id;
    _notify();
  }

  void toggleTool(String id, bool selected) =>
      toolSelection.toggle(id, selected);

  /// Reloads the method's tools, e.g. after managing them.
  Future<void> reloadTools() async {
    if (methodId case final method?) {
      await _loadTools(method, preferredIds: selectedToolIds);
    }
  }

  /// Fills the brew from a machine's shot, including when it was made.
  void applyGaggimateShot(GaggimateShot shot) {
    timer.stop();
    importedShot = null;
    importedFreePour = null;
    importedGaggimateShot = shot;
    brewedAt = shot.brewedAt;
    draft.applyGaggimateShot(shot);
    _notify();
  }

  void applyShot(MeticulousShot shot) {
    importedGaggimateShot = null;
    timer.stop();
    importedShot = shot;
    brewedAt = shot.brewedAt;
    draft.applyShot(shot);
    _notify();
  }

  /// Fills the filter brew from a free pour on the Meticulous's scale.
  void applyFreePour(MeticulousFreePour pour) {
    timer.stop();
    importedFreePour = pour;
    brewedAt = pour.brewedAt;
    draft.applyFreePour(pour);
    _notify();
  }

  void removeShot() {
    importedGaggimateShot = null;
    importedShot = null;
    importedFreePour = null;
    _notify();
  }

  /// Saves the brew, its imported shot and photos. Returns null when it is
  /// not ready to save; repository errors (such as
  /// [BrewCoffeeArchivedException]) propagate.
  Future<BrewSaveOutcome?> save({
    Future<FrozenPortion?> Function(List<FrozenPortion>, double)? chooseFrozen,
  }) async {
    final method = selectedMethod;
    final coffee = coffeeId;
    if (coffee == null || method == null || busy) return null;
    final grinder = grinders.where((row) => row.id == grinderId).firstOrNull;
    final grinderName = isPreGround
        ? null
        : grinder?.name ??
              (grinderTouched
                  ? null
                  : existing?.grinderName ??
                        (repeat ? seed?.grinderName : null));
    final espresso = isEspresso;
    final selectedLot = lotId;
    timer.stop();
    photoDraft.beginSave();
    saving = true;
    _notify();
    try {
      var source = pendingFrozenSource;
      if (existing == null &&
          source == null &&
          lotId != null &&
          chooseFrozen != null) {
        final lot = await repository.coffeeLot(lotId!);
        final needed = frozenGramsNeeded(
          parseNumber(draft.dose.text),
          lot?.remainingGrams == null
              ? null
              : lot!.remainingGrams! - (lot.overdrawGrams ?? 0),
        );
        if (needed > 0.000001) {
          final portions = (await repository.frozenPortionsForLot(lotId!))
              .where((p) => p.remainingGrams > 0)
              .toList();
          if (portions.isNotEmpty) {
            final chosen = await chooseFrozen(portions, needed);
            if (chosen == null || _disposed) return null;
            source = FrozenBrewSource(
              portionId: chosen.id,
              lotId: lotId!,
              grams: needed,
            );
          }
        }
      }
      if (_disposed || coffeeId != coffee || lotId != selectedLot) return null;
      return await BrewFormPersistence(repository, draft, photoDraft).save(
        id: existing?.id,
        coffeeId: coffee,
        lotId: lotId,
        frozenSource: source,
        method: method,
        grinder: grinder,
        grinderName: grinderName,
        waterProfileId: waterProfileId,
        recipient: recipient == null
            ? null
            : RecipientSnapshot(
                id: recipient!.id,
                name: recipient!.name,
                grams: recipient!.emptyGrams,
                isPortafilter: recipient!.isPortafilter,
              ),
        isPreGround: isPreGround,
        toolIds: selectedToolIds.toList(),
        espresso: espresso,
        grinderHasRpm: selectedGrinderHasRpm,
        rating: rating,
        brewedAt: brewedAt,
        shot: importedShot,
        gaggimateShot: gaggimateMethod == null ? null : importedGaggimateShot,
        freePour: importedFreePour,
        curve: devices.curve,
      );
    } finally {
      photoDraft.endSave();
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recipes.dispose();
    catalogs.dispose();
    toolSelection.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    photoDraft.dispose();
    timer.dispose();
    devices.dispose();
    draft.dispose();
    super.dispose();
  }
}
