import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'using a profile applies recipe and saves its snapshot; repeat keeps it',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repository = JournalRepository(db);
      final coffee = await repository.createCoffee(
        name: 'Coffee',
        roaster: 'R',
        initialGrams: 250,
      );
      final method = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
      final services = AppServices.forJournal(
        repository,
        parameterSettings: BrewParameterSettings(db),
      );
      final coffees = await repository.allCoffees();
      final model = BrewFormModel(
        services: services,
        coffees: coffees,
        initialCoffeeId: coffee,
        initialMethodId: method,
      );
      addTearDown(model.dispose);
      for (var i = 0; i < 500 && model.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(model.busy, isFalse);
      final profile = ExtractionProfile.example(
        'p',
        'Recipe',
      ).copyWith(doseGrams: 17, temperatureC: 91);
      model.timer.settle(25);
      model.useExtractionProfile(profile);
      expect(model.timer.elapsedSeconds, 0);
      expect(model.draft.dose.text, '17.0');
      expect(model.draft.temperature.text, '91.0');
      expect(model.draft.beverage.text, '38.0');
      expect(model.draft.profile.text, 'Recipe');
      expect(await model.save(), isNotNull);
      final brew = await db.select(db.brews).getSingle();
      expect(brew.extractionProfileJson, profile.encode());
      final repeat = BrewFormModel(
        services: services,
        coffees: coffees,
        seed: brew,
        repeat: true,
      );
      for (var i = 0; i < 500 && repeat.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repeat.extractionProfileJson, profile.encode());
      repeat.dispose();
    },
  );
}
