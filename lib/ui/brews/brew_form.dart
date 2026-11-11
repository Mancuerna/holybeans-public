import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_adjust_section.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_form_changes.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/brews/brew_frozen_picker.dart';
import 'package:holybeans/ui/brews/brew_recipe_header.dart';
import 'package:holybeans/ui/brews/gaggimate_shot_widgets.dart';
import 'package:holybeans/ui/brews/meticulous_free_pour_widgets.dart';
import 'package:holybeans/ui/brews/meticulous_shot_widgets.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_assistant_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/form_validation.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/motion.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/equipment_forms.dart';
import 'package:holybeans/ui/equipment/method_tools_sheet.dart';
import 'package:holybeans/ui/equipment/water_profile_form.dart';

class BrewFormResult {
  const BrewFormResult({
    required this.brewId,
    required this.coffeeId,
    required this.overdrawIncreased,
    this.rated = false,
  });

  final String brewId;
  final String coffeeId;
  final bool overdrawIncreased;

  /// Whether the saved brew has a rating.
  final bool rated;
}

class BrewForm extends StatefulWidget {
  const BrewForm({
    this.services,
    super.key,
    required this.coffees,
    this.existing,
    this.seed,
    this.initialCoffeeId,
    this.initialLotId,
    this.initialDoseGrams,
    this.initialFrozenSource,
    this.initialMethodId,
    this.repeat = false,
    this.adjust = false,
    this.savedPhotos = const [],
  });

  final AppServices? services;
  final List<Coffee> coffees;
  final Brew? existing;
  final Brew? seed;
  final String? initialCoffeeId;

  /// Inventory record and dose to preselect, e.g. after thawing a portion.
  final String? initialLotId;
  final double? initialDoseGrams;
  final FrozenBrewSource? initialFrozenSource;

  /// Method to preselect, e.g. from a method card.
  final String? initialMethodId;
  final bool repeat;

  /// Opens on what usually changes when tuning [seed] (grind, dose, water,
  /// temperature) with − and +, then the timer and the result; the rest of
  /// the form folds behind one button.
  final bool adjust;

  /// Photo files of [existing], in order.
  final List<String> savedPhotos;

  @override
  State<BrewForm> createState() => _BrewFormState();
}

class _BrewFormState extends State<BrewForm> {
  late final services = widget.services ?? AppServicesScope.read(context);
  final formKey = GlobalKey<FormState>();
  final _finalWeightKey = GlobalKey();
  bool _timerWasRunning = false;
  late final BrewFormModel model;
  late bool fullForm = !widget.adjust;
  bool _initialLoaded = false;
  late final BrewFormChanges changes;

  BrewDraft get draft => model.draft;

  @override
  void initState() {
    super.initState();
    model = BrewFormModel(
      services: services,
      coffees: widget.coffees,
      existing: widget.existing,
      seed: widget.seed,
      repeat: widget.repeat,
      initialCoffeeId: widget.initialCoffeeId,
      initialLotId: widget.initialLotId,
      initialDoseGrams: widget.initialDoseGrams,
      initialFrozenSource: widget.initialFrozenSource,
      initialMethodId: widget.initialMethodId,
      savedPhotos: widget.savedPhotos,
    );
    changes = BrewFormChanges(model);
    model.timer.addListener(_timerChanged);
    // Long brews must not lose the screen halfway.
    unawaited(const DeviceFeedback().keepScreenOn(true));
  }

  @override
  void dispose() {
    unawaited(const DeviceFeedback().keepScreenOn(false));
    model.timer.removeListener(_timerChanged);
    model.dispose();
    super.dispose();
  }

  void _timerChanged() {
    final stopped = _timerWasRunning && !model.timer.running;
    _timerWasRunning = model.timer.running;
    if (!stopped) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          model.timer.running ||
          model.isEspresso ||
          model.scaleSession?.curve == null ||
          (model.scaleSession?.restartsOnNextStart ?? false) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final target = _finalWeightKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.2,
        duration: motionDuration(target, const Duration(milliseconds: 300)),
        curve: Curves.easeOut,
      );
    });
  }

  String? _previousBrewYieldReference(AppLocalizations strings) {
    final value = widget.repeat ? widget.seed?.beverageGrams : null;
    if (value == null) return null;
    final amount = formatDecimal(
      value,
      pattern: '0.#',
      locale: regionalLocale.toString(),
    );
    return strings.previousBrewYieldReference(amount);
  }

  String? _previousBrewDurationReference(AppLocalizations strings) {
    final seconds = widget.repeat ? widget.seed?.timeSeconds : null;
    if (seconds == null) return null;
    final duration = formatDuration(seconds);
    return strings.previousBrewDurationReference(duration);
  }

  Future<void> _addMethod() async {
    final created = await showMethodForm(context, services.repository);
    if (created == null || !mounted) return;
    await model.methodCreated(created);
  }

  Future<void> _addGrinder() async {
    final created = await showGrinderForm(context, services.repository);
    if (created == null || !mounted) return;
    model.grinderCreated(created);
  }

  Future<void> _addWaterProfile() async {
    final created = await showWaterProfileForm(context, services.repository);
    if (created == null || !mounted) return;
    model.waterProfileCreated(created);
  }

  Future<void> _openPourAssistant() async {
    final result = await showPourAssistant(
      context,
      plan: model.pourPlanToStart(),
      scale: model.scaleSession?.scale,
    );
    if (result == null || !mounted) return;
    await model.applyPour(
      result.plan,
      result.totalSeconds,
      curve: result.curve,
      pouredGrams: result.pouredGrams,
    );
    if (mounted) {
      showMessage(context, AppLocalizations.of(context).pourResultApplied);
    }
  }

  Future<void> _manageTools() async {
    final selected = model.selectedMethod;
    if (selected == null) return;
    await showMethodTools(context, services.repository, selected);
    if (!mounted) return;
    await model.reloadTools();
  }

  /// Lets the user pick a shot of the method's Meticulous and fills the
  /// brew with it.
  Future<void> _importShot(BrewMethod method) async {
    if (method.machine == 'gaggimate') {
      final imported = await services.repository.importedGaggimateShots();
      if (!mounted) return;
      final shot = await pickGaggimateShot(
        context,
        address: method.machineAddress!,
        imported: imported,
      );
      if (shot != null && mounted && model.methodId == method.id) {
        model.applyGaggimateShot(shot);
      }
      return;
    }
    final imported = await services.repository.importedMeticulousShots();
    if (!mounted) return;
    final shot = await pickMeticulousShot(
      context,
      address: method.machineAddress!,
      imported: imported,
    );
    if (shot != null && mounted) model.applyShot(shot);
  }

  /// Shows the latest free pour on the Meticulous's scale and fills the
  /// filter brew with it.
  Future<void> _importFreePour(String address) async {
    final imported = await services.repository.importedMeticulousFreePours();
    if (!mounted) return;
    final pour = await pickMeticulousFreePour(
      context,
      address: address,
      imported: imported,
    );
    if (pour != null && mounted) model.applyFreePour(pour);
  }

  Future<void> save() async {
    final s = AppLocalizations.of(context);
    if (!model.isEspresso && !draft.hasValidPourDetails) {
      draft.pours.detailsExpanded = true;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    if (!await validateAndReveal(formKey.currentState!)) return;
    if (!mounted) return;
    if (model.selectedMethod == null) {
      showMessage(context, s.brewNeedsMethod);
      return;
    }
    if (model.pendingFrozenSource != null &&
        parseNumber(draft.dose.text) == null) {
      showMessage(context, s.brewFrozenNeedsDose);
      return;
    }
    if (!model.isEspresso && !draft.hasValidPourDetails) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.pourDetailsInvalid)));
      return;
    }
    try {
      final outcome = await model.save(
        chooseFrozen: (portions, grams) async {
          if (!mounted) return null;
          return chooseFrozenForBrew(context, portions, grams);
        },
      );
      if (outcome == null || !mounted) return;
      FormExitGuard.complete(
        context,
        BrewFormResult(
          brewId: outcome.id,
          coffeeId: outcome.coffeeId,
          overdrawIncreased: outcome.overdrawIncreased,
          rated: model.rating != null,
        ),
      );
    } on BrewStockReviewRequiredException {
      if (mounted) showMessage(context, s.stockReviewRequired);
    } on BrewArchivedWithCoffeeException {
      if (mounted) showMessage(context, s.restoreCoffeeFirst);
    } on BrewCoffeeArchivedException {
      if (mounted) showMessage(context, s.coffeeArchivedCannotBrew);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
      final draft = model.draft;
      final recipeInputs = Listenable.merge([draft.dose, draft.water]);
      Widget result() => ListenableBuilder(
        listenable: Listenable.merge([
          draft.dose,
          draft.water,
          draft.beverage,
          draft.tds,
          draft.brix,
          draft.brixFactor,
        ]),
        builder: (_, _) => BrewResultSection(
          model: model,
          finalWeightKey: _finalWeightKey,
          photos: services.photos,
          previousYield: _previousBrewYieldReference(s),
        ),
      );
      final BrewFormActions actions = (
        addMethod: _addMethod,
        addGrinder: _addGrinder,
        addWaterProfile: _addWaterProfile,
        manageTools: _manageTools,
        openPourAssistant: _openPourAssistant,
        importShot: _importShot,
        importFreePour: _importFreePour,
      );
      final repeatedWaterProfile = widget.repeat
          ? model.waterProfiles
                .where((option) => option.id == widget.seed?.waterProfileId)
                .firstOrNull
          : null;
      changes.settleInitial();
      // Reveal the first snapshot together. Later loads must keep the mounted
      // fields and everything the user has already entered.
      if (!model.busy) _initialLoaded = true;
      return FormExitGuard(
        hasChanges: () => _initialLoaded && changes.changed,
        busy: () => model.saving || model.photoDraft.picking,
        child: Listener(
          onPointerDown: (_) {
            if (_initialLoaded) changes.interacted();
          },
          child: SheetFrame(
            title: widget.existing != null
                ? s.editBrew
                : widget.adjust
                ? s.adjustBrew
                : widget.repeat
                ? s.repeatBrew
                : s.formPreviewTitle,
            header: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_initialLoaded && !model.loadingMethods)
                  BrewRecipeHeader(model: model),
                if (model.hasLoadError)
                  ListTile(
                    key: const ValueKey('brew-load-error'),
                    title: Text(s.dataError),
                    trailing: TextButton(
                      onPressed: model.retryLoads,
                      child: Text(s.retry),
                    ),
                  ),
              ],
            ),
            formKey: formKey,
            saving: model.busy,
            onSave: save,
            showScrollCue: true,
            children: [
              if (!_initialLoaded) ...[
                if (!model.hasLoadError) const _InitialBrewLoading(),
              ] else
                // A handful of sections form one scroll child. Keeping them
                // mounted avoids fractional sliver estimates when returning
                // to the first section and preserves field state off screen.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: [
                    if (model.loadingMethods && !fullForm)
                      const LinearProgressIndicator()
                    else if (!fullForm) ...[
                      ...brewHelpCards(model, actions),
                      ListenableBuilder(
                        listenable: recipeInputs,
                        builder: (_, _) =>
                            BrewAdjustSection(model: model, seed: widget.seed),
                      ),
                      ListTile(
                        key: const ValueKey('brew-full-form'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.unfold_more_rounded),
                        title: Text(s.adjustFullForm),
                        subtitle: Text(s.adjustFullFormHint),
                        onTap: () => setState(() => fullForm = true),
                      ),
                      BrewTimingSection(
                        model: model,
                        previousDuration: _previousBrewDurationReference(s),
                      ),
                      result(),
                    ] else ...[
                      BrewChoiceSection(
                        model: model,
                        coffees: widget.coffees,
                        isNew: widget.existing == null && !widget.repeat,
                        actions: actions,
                      ),
                      BrewEquipmentSection(
                        model: model,
                        actions: actions,
                        existingWaterProfileId: widget.existing?.waterProfileId,
                        repeatedWaterProfileName:
                            repeatedWaterProfile?.archivedAtMs == null
                            ? null
                            : widget.seed?.waterProfileName ??
                                  repeatedWaterProfile!.name,
                      ),
                      if (!model.loadingMethods) ...[
                        ListenableBuilder(
                          listenable: recipeInputs,
                          builder: (_, _) =>
                              BrewRecipeSection(model: model, actions: actions),
                        ),
                        BrewTimingSection(
                          model: model,
                          previousDuration: _previousBrewDurationReference(s),
                        ),
                        result(),
                      ],
                    ],
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _InitialBrewLoading extends StatefulWidget {
  const _InitialBrewLoading();

  @override
  State<_InitialBrewLoading> createState() => _InitialBrewLoadingState();
}

class _InitialBrewLoadingState extends State<_InitialBrewLoading> {
  late final Timer _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Most local reads finish during the sheet animation; avoid flashing an
    // indicator for those, but keep feedback for a genuinely slow load.
    _timer = Timer(const Duration(milliseconds: 250), () {
      setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: _visible ? const Center(child: CircularProgressIndicator()) : null,
  );
}
