import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_fields.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';
import 'package:holybeans/ui/brews/brew_ratio_slider.dart';
import 'package:holybeans/ui/brews/brew_scale_reset_button.dart';
import 'package:holybeans/ui/brews/brew_water_plan.dart';
import 'package:holybeans/ui/brews/brew_weight_chart.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/brews/dial_in_card.dart';
import 'package:holybeans/ui/brews/extraction_timer.dart';
import 'package:holybeans/ui/brews/gaggimate_shot_widgets.dart';
import 'package:holybeans/ui/brews/meticulous_free_pour_widgets.dart';
import 'package:holybeans/ui/brews/meticulous_shot_widgets.dart';
import 'package:holybeans/ui/brews/portafilter_weighing.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_reference_page.dart';
import 'package:holybeans/ui/brews/refractometer_button.dart';
import 'package:holybeans/ui/core/detail_widgets.dart' show formatGrams;
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/suggested_text_field.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';

/// The brew form in the order of brewing: what is brewed, the equipment,
/// the recipe, the timing with its devices, and the result. Each section
/// lays its fields out like the form's list (20 between them) and leaves
/// hidden parameters out.
const _fieldGap = 20.0;

/// Actions of the form that open other screens.
typedef BrewFormActions = ({
  VoidCallback addMethod,
  VoidCallback addGrinder,
  VoidCallback addWaterProfile,
  VoidCallback manageTools,
  VoidCallback openPourAssistant,
  void Function(BrewMethod method) importShot,
  void Function(String address) importFreePour,
});

/// "Ratio: 1:16" for what is typed, or null.
String? _ratio(BrewFormModel model, AppLocalizations s) => formatBrewRatio(
  methodCategory: model.selectedMethod?.category,
  methodName: model.methodName,
  doseGrams: parseNumber(model.draft.dose.text),
  waterGrams: parseNumber(model.draft.water.text),
  beverageGrams: parseNumber(model.draft.beverage.text),
  localeName: regionalLocale.toString(),
);

/// With a paired scale, a weight field gets a button taking its reading.
Widget? _scaleFill(
  BrewFormModel model,
  TextEditingController field,
  String key,
) => switch (model.scaleSession) {
  final session? => ScaleFillButton(
    key: ValueKey(key),
    scale: session.scale,
    onUse: (grams) => model.draft.fillWeight(field, grams),
  ),
  null => null,
};

class _Section extends StatelessWidget {
  const _Section(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: _fieldGap,
    children: children,
  );
}

/// Date, coffee and lot, method with the last brew and the machine's shot,
/// profile, tools and the method memory hint.
class BrewChoiceSection extends StatelessWidget {
  const BrewChoiceSection({
    super.key,
    required this.model,
    required this.coffees,
    required this.isNew,
    required this.actions,
  });

  final BrewFormModel model;
  final List<Coffee> coffees;

  /// A new brew, neither edited nor repeated.
  final bool isNew;
  final BrewFormActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final draft = model.draft;
    final activeMethods = [
      for (final row in model.methods)
        if (row.archivedAtMs == null || row.id == model.methodId) row,
    ];
    return _Section([
      BrewDateTimeChips(value: model.brewedAt, onChanged: model.setBrewedAt),
      CoffeePicker(
        repository: model.repository,
        coffees: coffees,
        value: model.coffeeId,
        onChanged: model.selectCoffee,
      ),
      if (model.loadingLots)
        const LinearProgressIndicator()
      else if (model.lots.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(s.noInventoryRecorded),
        )
      else if (model.lots.length > 1)
        DropdownButtonFormField<String>(
          key: ValueKey('${model.coffeeId ?? ''}-${model.lotId ?? ''}'),
          initialValue: model.lotId,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.inventoryLot),
          items: [
            for (final (index, lot) in model.lots.indexed)
              DropdownMenuItem(
                value: lot.id,
                child: Text(
                  inventoryLotLabel(lot, index + 1, s),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: model.selectLot,
        ),
      if (model.loadingMethods)
        const LinearProgressIndicator()
      else if (activeMethods.isEmpty)
        Row(
          children: [
            Expanded(child: Text(s.noActiveMethods)),
            TextButton.icon(
              onPressed: actions.addMethod,
              icon: const Icon(Icons.add_rounded),
              label: Text(s.addMethod),
            ),
          ],
        )
      else
        DropdownWithAdd(
          fieldKey: ValueKey('method:${model.methodId}'),
          value: model.methodId,
          label: s.selectMethod,
          items: [
            for (final row in activeMethods) catalogItem(row.id, row.name),
          ],
          onChanged: model.selectMethod,
          validator: (value) => value == null ? s.requiredField : null,
          addTooltip: s.addMethod,
          onAdd: actions.addMethod,
        ),
      ...brewHelpCards(model, actions),
      if ((model.isEspresso || draft.profile.text.trim().isNotEmpty) &&
          model.shows(BrewParameter.profile))
        SuggestedTextField(
          key: ValueKey('profile-method:${model.methodId}'),
          fieldKey: const ValueKey('brew-profile'),
          suggestions: model.profileSuggestions,
          suggestionsAbove: true,
          controller: draft.profile,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: s.profileName,
            counterText: '',
          ),
        ),
      if (model.methodId != null && model.shows(BrewParameter.tools))
        model.loadingTools
            ? const LinearProgressIndicator()
            : MethodToolChips(
                tools: model.tools,
                useCounts: model.toolUseCounts,
                selected: model.selectedToolIds,
                onToggle: model.toggleTool,
                onManage: actions.manageTools,
              ),
      if (model.memoryMethodName case final name? when isNew)
        MethodMemoryHint(
          name,
          key: const ValueKey('method-memory-hint'),
          favorite: model.memoryFromFavorite,
        ),
    ]);
  }
}

/// The last brew of the coffee and method with its advice, and the shot or
/// free pour the method's Meticulous can fill the brew with: what helps to
/// tune the next brew, so the short Adjust form shows it too.
List<Widget> brewHelpCards(BrewFormModel model, BrewFormActions actions) => [
  if (model.favorite case final favorite?)
    DialInCard(
      brew: favorite,
      rated: true,
      favorite: true,
      latest: model.dialIn?.id == favorite.id ? null : model.dialIn,
      newest: model.newestBrew,
      editingId: model.existing?.id,
    )
  else if (model.dialIn case final last?)
    DialInCard(
      brew: last,
      rated: model.dialInRated,
      newest: model.newestBrew,
      editingId: model.existing?.id,
    ),
  if (model.gaggimateMethod case final method?)
    GaggimateShotCard(
      shot: model.importedGaggimateShot,
      onImport: () => actions.importShot(method),
      onRemove: model.removeShot,
    ),
  if (model.meticulousMethod case final method?)
    MeticulousShotCard(
      shot: model.importedShot,
      onImport: () => actions.importShot(method),
      onRemove: model.removeShot,
    ),
  if (model.freePourAddress case final address?)
    MeticulousFreePourCard(
      pour: model.importedFreePour,
      onImport: () => actions.importFreePour(address),
      onRemove: model.removeShot,
    ),
];

/// The espresso target ratio or the filter ratio with its shortcuts.
Widget brewRatioControl(BrewFormModel model) {
  final draft = model.draft;
  return BrewRatioSlider(
    espresso: model.isEspresso,
    doseGrams: parseNumber(draft.dose.text),
    ratio: model.isEspresso
        ? model.espressoTargetRatio
        : filterRecipeRatio(
            parseNumber(draft.dose.text),
            parseNumber(draft.water.text),
          ),
    onChanged: (value) {
      if (model.isEspresso) {
        model.setEspressoTargetRatio(value);
      } else if (brewRatioTargetGrams(
            doseGrams: parseNumber(draft.dose.text),
            ratio: value,
          )
          case final grams?) {
        draft.water.text = fieldNumber(grams, decimals: 1);
      }
    },
  );
}

/// Grinder (or pre-ground), grind setting and speed, and water profile.
class BrewEquipmentSection extends StatelessWidget {
  const BrewEquipmentSection({
    super.key,
    required this.model,
    required this.actions,
    this.existingWaterProfileId,
    this.repeatedWaterProfileName,
  });

  static const _noWaterProfile = '';

  final BrewFormModel model;
  final BrewFormActions actions;

  /// The edited brew's water profile, kept even when archived.
  final String? existingWaterProfileId;

  /// A repeated brew's archived water profile, shown as a reference.
  final String? repeatedWaterProfileName;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    const preGround = BrewFormModel.preGroundChoice;
    return _Section([
      if (model.shows(BrewParameter.grinder))
        model.loadingGrinders
            ? const LinearProgressIndicator()
            : DropdownWithAdd(
                fieldKey: ValueKey(
                  'grinder:${model.isPreGround ? preGround : model.grinderId ?? ''}',
                ),
                value: model.isPreGround ? preGround : model.grinderId ?? '',
                label: s.grinder,
                items: [
                  catalogItem('', s.unspecifiedGrinder),
                  catalogItem(preGround, s.preGround),
                  for (final row in model.grinders)
                    if (row.archivedAtMs == null || row.id == model.grinderId)
                      catalogItem(row.id, row.name),
                ],
                onChanged: (value) {
                  if (value != null) model.selectGrinder(value);
                },
                addTooltip: s.addGrinder,
                onAdd: actions.addGrinder,
              ),
      if (!model.isPreGround && model.shows(BrewParameter.grindSetting))
        TextFormField(
          controller: model.draft.grindSetting,
          decoration: InputDecoration(labelText: s.grindSetting),
        ),
      if (model.selectedGrinderHasRpm && model.shows(BrewParameter.grindRpm))
        IntegerField(
          key: const ValueKey('brew-grind-rpm'),
          controller: model.draft.grindRpm,
          label: s.grindRpm,
        ),
      if (model.selectedGrinderHasFeederRpm &&
          model.shows(BrewParameter.feederRpm))
        IntegerField(
          key: const ValueKey('brew-feeder-rpm'),
          controller: model.draft.feederRpm,
          label: s.feederRpm,
        ),
      if (model.shows(BrewParameter.waterProfile)) ...[
        if (model.loadingWaterProfiles)
          const LinearProgressIndicator()
        else
          DropdownWithAdd(
            fieldKey: ValueKey('water-profile:${model.waterProfileId ?? ''}'),
            value: model.waterProfileId ?? _noWaterProfile,
            label: s.brewWaterProfile,
            items: [
              catalogItem(_noWaterProfile, s.noWaterProfile),
              for (final option in model.waterProfiles)
                if (option.archivedAtMs == null ||
                    (existingWaterProfileId == option.id &&
                        model.waterProfileId == option.id))
                  catalogItem(
                    option.id,
                    option.archivedAtMs == null
                        ? option.name
                        : '${option.name}, ${s.archivedStatus}',
                    enabled: option.archivedAtMs == null,
                  ),
            ],
            onChanged: model.selectWaterProfile,
            addTooltip: s.addWaterProfile,
            onAdd: actions.addWaterProfile,
          ),
        if (repeatedWaterProfileName case final name?)
          Text(
            s.archivedWaterReference(name),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ]);
  }
}

class BrewPoursSection extends StatelessWidget {
  const BrewPoursSection({super.key, required this.model});

  final BrewFormModel model;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    return _Section([
      BrewPoursFields(
        draft: draft.pours,
        dose: draft.dose,
        showBlooms: model.shows(BrewParameter.bloomCount),
        showPours: model.shows(BrewParameter.pourCount),
        showDetails: model.shows(BrewParameter.pourDetails),
        bloomTime: model.shows(BrewParameter.bloom) ? draft.bloom : null,
      ),
      if (model.shows(BrewParameter.bloomCount) &&
          model.shows(BrewParameter.pourCount))
        BrewWaterPlan(
          draft: draft.pours,
          dose: draft.dose,
          water: draft.water,
          timer: model.timer,
          showTimer: model.timerAtWaterPlan,
          bloom: model.shows(BrewParameter.bloom) ? draft.bloom : null,
          scale: model.scaleSession,
          waterTarget: () => model.devices.filterWaterTarget,
        ),
    ]);
  }
}

/// Dose and, outside espresso, water with ratio shortcuts; temperature;
/// pressure and pre-infusion for espresso; the pour assistant for filter.
class BrewRecipeSection extends StatelessWidget {
  const BrewRecipeSection({
    super.key,
    required this.model,
    required this.actions,
  });

  final BrewFormModel model;
  final BrewFormActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final draft = model.draft;
    final dose = numberField(
      context,
      draft.dose,
      '${s.dose} (g)',
      suffix: model.isEspresso && model.recipient != null
          ? null
          : _scaleFill(model, draft.dose, 'scale-to-dose'),
    );
    // Espresso is set by its dose; the yield is a result. Filter and
    // immersion brews also set their water, with ratio shortcuts.
    return _Section([
      Text(s.recipeSection, style: Theme.of(context).textTheme.titleMedium),
      if (model.pendingFrozenSource case final source?)
        Text(
          s.brewThawOnSave(
            formatGrams(source.grams, regionalLocale.toString()),
          ),
          key: const ValueKey('brew-thaw-on-save'),
        ),
      if (model.isEspresso)
        dose
      else ...[
        FieldPair(
          dose,
          model.shows(BrewParameter.water)
              ? numberField(context, draft.water, '${s.water} (g)')
              : null,
        ),
      ],
      if (model.isEspresso) PortafilterWeighButton(model: model),
      if (model.shows(BrewParameter.ratio) &&
          (model.isEspresso || model.shows(BrewParameter.water)))
        brewRatioControl(model),
      if (!model.isEspresso) BrewPoursSection(model: model),
      if (model.shows(BrewParameter.temperature))
        numberField(
          context,
          draft.temperature,
          '${s.temperature} (°C)',
          positive: false,
        ),
      if (model.isEspresso &&
          (model.shows(BrewParameter.pressure) ||
              model.shows(BrewParameter.preinfusion)))
        FieldPair(
          model.shows(BrewParameter.pressure)
              ? numberField(
                  context,
                  draft.pressure,
                  s.pressureBar,
                  positive: false,
                  max: 30,
                  key: const ValueKey('brew-pressure'),
                )
              : null,
          model.shows(BrewParameter.preinfusion)
              ? IntegerField(
                  key: const ValueKey('brew-preinfusion'),
                  controller: draft.preinfusion,
                  label: s.preinfusionSeconds,
                )
              : null,
        ),
      if (model.isEspresso && model.isNew)
        PressureAssistantButton(model: model),
      if (!model.isEspresso &&
          model.methodId != null &&
          model.selectedMethod?.category?.trim().toLowerCase() != 'immersion')
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('pour-assistant'),
            onPressed: actions.openPourAssistant,
            icon: const Icon(Icons.water_drop_outlined),
            label: Text(s.pourAssistant),
          ),
        ),
    ]);
  }
}

/// The timer (with "Wait for drip" and phase marks), first drip, the scale
/// and pressure sensor lines, and the weight curve drawn live with a Stop button.
class BrewTimingSection extends StatelessWidget {
  const BrewTimingSection({
    super.key,
    required this.model,
    this.previousDuration,
    this.liveChartKey,
  });

  final BrewFormModel model;
  final Key? liveChartKey;

  /// The repeated brew's time, as a reference.
  final String? previousDuration;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model.scaleSession ?? model.timer,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final s = AppLocalizations.of(context);
    final draft = model.draft;
    final espresso = model.isEspresso;
    final scale = model.scaleSession;
    // With a connected scale (or its curve), the weight chart holds the
    // timer's start and stop, and the chart shows before anything is
    // recorded.
    bool chartShown() =>
        scale != null && (scale.scale.connected || scale.curve != null);
    return _Section([
      ListenableBuilder(
        listenable: Listenable.merge([?scale, model.timer]),
        builder: (context, _) => ExtractionTimerField(
          timer: model.timer,
          previousDuration: previousDuration,
          showToggle: !chartShown() && !model.timerAtWaterPlan,
          marks: [
            if (espresso && model.shows(BrewParameter.preinfusion))
              (field: draft.preinfusion, label: s.markPreinfusion),
            if (espresso && model.shows(BrewParameter.firstDrip))
              (field: draft.firstDrip, label: s.firstDrip),
            // A scale recording finds the blooms on its curve instead.
            if (!espresso &&
                draft.pours.bloomCount != 0 &&
                model.shows(BrewParameter.bloom) &&
                !(scale?.recording ?? false))
              (field: draft.bloom, label: s.markBloom),
          ],
        ),
      ),
      if (espresso && model.shows(BrewParameter.firstDrip))
        IntegerField(
          key: const ValueKey('brew-first-drip'),
          controller: draft.firstDrip,
          label: s.firstDripSeconds,
        ),
      if (scale != null)
        ScaleStatusRow(
          scale: scale.scale,
          busy: scale.resetting,
          resetAction: BrewScaleResetButton(session: scale, timer: model.timer),
          extraAction:
              espresso &&
                  !model.timer.running &&
                  model.timer.elapsedSeconds == 0
              ? scale.waitingForDrip
                    ? OutlinedButton.icon(
                        key: const ValueKey('scale-wait-drip-cancel'),
                        onPressed: scale.cancelWaitForDrip,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(s.scaleCancelWaitDrip),
                      )
                    : Tooltip(
                        message: s.scaleWaitDripHint,
                        child: FilledButton.icon(
                          key: const ValueKey('scale-wait-drip'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onPressed: scale.scale.connected && !scale.resetting
                              ? scale.waitForDrip
                              : null,
                          icon: const Icon(Icons.water_drop_outlined, size: 18),
                          label: Text(s.scaleWaitDrip),
                        ),
                      )
              : null,
          footerIcon: scale.waitingForDrip ? Icons.water_drop_outlined : null,
          footer: scale.waitingForDrip
              ? s.scaleWaitingDrip
              : scale.recording
              ? s.scaleRecording
              : switch (scale.curve) {
                  final curve? => s.scaleCurveRecorded(
                    formatDecimal(
                      curve.durationMs / 1000,
                      pattern: '0',
                      locale: regionalLocale.toString(),
                    ),
                  ),
                  null => null,
                },
        ),
      if (model.pressureSession case final session? when espresso)
        PressureStatusRow(
          sensor: session.sensor,
          footer: session.recording
              ? s.sensorRecording
              : switch (session.peakBar) {
                  final peak? => s.sensorPeak(
                    formatDecimal(
                      peak,
                      pattern: '0.0',
                      locale: regionalLocale.toString(),
                    ),
                  ),
                  null => null,
                },
        ),
      if (scale?.startFailed ?? false) Text(s.scaleStartFailed),
      if (scale != null) BrewWeightChart(key: liveChartKey, model: model),
    ]);
  }
}

/// Yield (or jug weight), TDS, ratio and EY, rating, notes and photos.
class BrewResultSection extends StatelessWidget {
  const BrewResultSection({
    super.key,
    required this.model,
    this.photos,
    this.previousYield,
    this.finalWeightKey,
  });

  final BrewFormModel model;
  final PhotoStore? photos;
  final Key? finalWeightKey;

  /// The repeated brew's yield, as a reference.
  final String? previousYield;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final draft = model.draft;
    final espresso = model.isEspresso;
    final ratio = _ratio(model, s);
    final ey = extractionYieldPercent(
      doseGrams: parseNumber(draft.dose.text),
      beverageGrams: parseNumber(draft.beverage.text),
      tdsPercent: draft.effectiveTds,
    );
    final beverage = model.shows(BrewParameter.beverage)
        ? numberField(
            context,
            draft.beverage,
            '${s.brewOutput} (g)',
            helperText: previousYield,
            suffix: model.jugGrams == null
                ? _scaleFill(model, draft.beverage, 'scale-to-beverage')
                : null,
          )
        : null;
    final refractometer = model.devices.refractometer;
    Widget tdsField() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: s.measureBrix,
          toggled: draft.brixMode,
          onTap: () => model.setBrixMode(!draft.brixMode),
          excludeSemantics: true,
          child: SwitchListTile.adaptive(
            title: Text(s.measureBrix),
            value: draft.brixMode,
            onChanged: model.setBrixMode,
          ),
        ),
        if (draft.brixMode) ...[
          numberField(context, draft.brix, s.brix, max: 100),
          const SizedBox(height: 16),
          numberField(
            context,
            draft.brixFactor,
            s.brixFactor,
            max: 1,
            validate: (v) => draft.brix.text.trim().isNotEmpty && v == null
                ? s.invalidNumber
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            '${s.estimatedTds}: ${draft.effectiveTds == null ? '—' : formatDecimal(draft.effectiveTds, pattern: '0.00', locale: regionalLocale.toString())} %',
          ),
          Text(s.brixHint),
        ] else
          numberField(
            context,
            draft.tds,
            '${s.tds} (%)',
            max: 100,
            helperText: switch (model.devices.measureProblem.value) {
              R2Failed() => s.refractometerFailed,
              R2Result(:final tdsPercent) => s.refractometerBelowZero(
                formatDecimal(
                  tdsPercent,
                  pattern: '0.00',
                  locale: regionalLocale.toString(),
                ),
              ),
              _ => null,
            },
            // With the refractometer connected, a button measures the sample.
            suffix: refractometer != null && refractometer.connected
                ? RefractometerButton(refractometer: refractometer)
                : null,
          ),
      ],
    );
    final tds = !model.shows(BrewParameter.tds)
        ? null
        : refractometer == null
        ? tdsField()
        : ListenableBuilder(
            listenable: Listenable.merge([
              refractometer,
              model.devices.measureProblem,
            ]),
            builder: (context, _) => tdsField(),
          );
    return _Section([
      Text(s.resultSection, style: Theme.of(context).textTheme.titleMedium),
      if (!espresso && model.shows(BrewParameter.beverage))
        RecipientPicker(
          repository: model.repository,
          value: model.recipient?.id,
          snapshot: model.recipient,
          onChanged: model.selectRecipient,
        ),
      // Weighing the beverage in the selected recipient subtracts its tare.
      if (model.jugGrams case final jug?
          when model.shows(BrewParameter.beverage))
        KeyedSubtree(
          key: finalWeightKey,
          child: numberField(
            context,
            draft.jugTotal,
            s.weightWithJug,
            key: const ValueKey('brew-jug-total'),
            validate: (total) =>
                total != null && total <= jug ? s.recipientTooHeavy : null,
            suffix: _scaleFill(model, draft.jugTotal, 'scale-to-jug-total'),
            helperText: s.jugTare(
              model.recipient?.name ?? s.jug,
              formatDecimal(
                jug,
                pattern: '0.#',
                locale: regionalLocale.toString(),
              ),
            ),
          ),
        ),
      if (beverage != null || tds != null)
        FieldPair(
          beverage != null && model.jugGrams == null
              ? KeyedSubtree(key: finalWeightKey, child: beverage)
              : beverage,
          tds,
          minimumRowWidth: 560,
        ),
      if (espresso && ratio != null && model.shows(BrewParameter.ratio))
        Text('${s.ratio}: $ratio'),
      if (ey != null && model.shows(BrewParameter.ey))
        Text(
          '${s.ey}${draft.brixMode ? ' ≈' : ''}: ${formatDecimal(ey, pattern: '0.#', locale: regionalLocale.toString())} %',
        ),
      if (model.shows(BrewParameter.rating))
        OptionalRatingSlider(value: model.rating, onChanged: model.setRating),
      if (model.shows(BrewParameter.notes))
        TextFormField(
          controller: draft.notes,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: InputDecoration(labelText: s.notes),
        ),
      if (photos case final store? when model.shows(BrewParameter.photos))
        PhotosField(store: store, draft: model.photoDraft, label: s.brewPhoto),
    ]);
  }
}
