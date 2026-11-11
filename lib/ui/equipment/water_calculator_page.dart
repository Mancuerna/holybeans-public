import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_alternatives_picker.dart';
import 'package:holybeans/ui/equipment/water_calculator_inputs.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';
import 'package:holybeans/ui/equipment/water_profile_form.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showWaterCalculator(
  BuildContext context,
  JournalRepository repository, {
  WaterRecipe? seed,
  WaterProfile? initialWater,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => WaterCalculatorPage(
      repository: repository,
      seed: seed,
      initialWater: initialWater,
    ),
  ),
);

class WaterCalculatorPage extends StatefulWidget {
  const WaterCalculatorPage({
    super.key,
    required this.repository,
    this.seed,
    this.initialWater,
  });
  final JournalRepository repository;
  final WaterRecipe? seed;
  final WaterProfile? initialWater;

  @override
  State<WaterCalculatorPage> createState() => _WaterCalculatorPageState();
}

class _WaterCalculatorPageState extends State<WaterCalculatorPage> {
  late final model = WaterCalculatorModel(
    seed: widget.seed,
    initialWater: widget.initialWater,
  );
  late final savedProfiles = widget.repository.watchWaterProfiles().first;
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    final recipe = model.recipe;
    if (recipe == null) return;
    final result = recipe.result;
    final saved = await showWaterProfileForm(
      context,
      widget.repository,
      initial: WaterProfile(
        id: '',
        name: '',
        ghPpmAsCaCO3: result.gh,
        khPpmAsCaCO3: result.kh,
        calciumPpm: result[WaterIon.calcium],
        magnesiumPpm: result[WaterIon.magnesium],
        sodiumPpm: result[WaterIon.sodium],
        potassiumPpm: result[WaterIon.potassium],
        chloridePpm: result[WaterIon.chloride],
        sulfatePpm: result[WaterIon.sulfate],
        bicarbonatePpm: result[WaterIon.bicarbonate],
        recipeJson: recipe.toJson(),
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).waterProfileSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.waterCalculator)),
      body: FutureBuilder<List<WaterProfile>>(
        future: savedProfiles,
        builder: (context, snapshot) => ListenableBuilder(
          listenable: model,
          builder: (context, _) => Form(
            key: formKey,
            child: ListView(
              key: const ValueKey('water-calculator-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                WaterCalculatorInputs(
                  model: model,
                  savedProfiles: snapshot.data ?? [],
                ),
                const SizedBox(height: 24),
                WaterAlternativesPicker(model: model),
                if (model.recipe case final recipe?)
                  WaterCalculatorResult(recipe: recipe, showDerived: true)
                else
                  Text(
                    model.missingTarget
                        ? s.waterMissingTarget
                        : model.missingMixtureBase
                        ? s.waterMixtureMissingBase
                        : model.missingBase
                        ? s.waterMissingBase
                        : s.waterInvalidCalculation,
                    key: const ValueKey('water-calculation-error'),
                  ),
                if (model.mode == WaterCalculationMode.preset &&
                    !model.isSavedTarget)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(model.preset.source),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(s.waterRecipeSource),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) => FilledButton.icon(
              key: const ValueKey('water-save-result'),
              onPressed: model.recipe == null ? null : _save,
              icon: const Icon(Icons.add),
              label: Text(s.waterSaveResult),
            ),
          ),
        ),
      ),
    );
  }
}
