import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/profile_suggestions.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

class _DelayedProfiles extends JournalRepository {
  _DelayedProfiles(super.database);
  final result = Completer<ProfileSuggestions>();

  @override
  Future<ProfileSuggestions> profileSuggestions() => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late JournalRepository repository;
  late String coffee;
  late String method;
  late String other;
  setUp(() async {
    db = memoryDatabase();
    repository = JournalRepository(db);
    coffee = await repository.createCoffee(name: 'Beans', roaster: 'Test');
    method = await repository.createMethod(
      name: 'Classic',
      category: 'espresso',
    );
    other = await repository.createMethod(name: 'Lever', category: 'espresso');
    final id = await repository.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'Classic',
      profileName: 'Plano sin preinfusión',
      doseGrams: 18,
      temperatureC: 93,
      brewedAt: DateTime(2026),
    );
    await (db.update(db.brews)..where((row) => row.id.equals(id))).write(
      const BrewsCompanion(archivedAtMs: Value(1)),
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodId: other,
      methodName: 'Lever',
      profileName: 'Plano con preinfusión',
      brewedAt: DateTime(2026, 2),
    );
  });
  tearDown(() => db.close());

  test('reads archived history, keeps method identity after rename, and learns saved names', () async {
    await (db.update(db.brewMethods)..where((row) => row.id.equals(method)))
        .write(const BrewMethodsCompanion(name: Value('Renamed')));
    final before = await repository.allBrews();
    expect((await repository.profileSuggestions()).forMethod(method), [
      'Plano sin preinfusión',
      'Plano con preinfusión',
    ]);
    expect(await repository.allBrews(), before);
    await repository.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'Renamed',
      profileName: 'Mi perfil nuevo',
    );
    expect(
      (await repository.profileSuggestions()).forMethod(method).first,
      'Mi perfil nuevo',
    );
  });

  for (final locale in ['es', 'en']) {
    testWidgets('profile selection changes only its editable name in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(locale),
          home: Scaffold(
            body: BrewForm(
              services: AppServices.forJournal(
                repository,
                parameterSettings: BrewParameterSettings(db),
              ),

              coffees: await repository.allCoffees(),
              initialCoffeeId: coffee,
              initialMethodId: method,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final model = tester
          .widget<BrewChoiceSection>(find.byType(BrewChoiceSection))
          .model;
      model.draft.dose.text = '19';
      model.draft.temperature.text = '94';
      final profile = find.byKey(const ValueKey('brew-profile'));
      await tester.ensureVisible(profile);
      await tester.enterText(profile, 'PLA');
      await tester.pumpAndSettle();
      final options = find
          .byType(ListTile)
          .evaluate()
          .map((element) => element.widget as ListTile)
          .map((tile) => tile.title)
          .whereType<Text>()
          .map((text) => text.data)
          .toList();
      expect(
        options.indexOf('Plano sin preinfusión'),
        lessThan(options.indexOf('Plano con preinfusión')),
      );
      await tester.tap(find.text('Plano sin preinfusión').last);
      await tester.pumpAndSettle();
      expect(model.draft.profile.text, 'Plano sin preinfusión');
      expect(model.draft.dose.text, '19');
      expect(model.draft.temperature.text, '94');
      await tester.enterText(profile, 'Mi perfil libre');
      await tester.pumpAndSettle();
      expect(model.draft.profile.text, 'Mi perfil libre');
      await model.selectMethod(other);
      await tester.pumpAndSettle();
      await tester.ensureVisible(profile);
      await tester.enterText(profile, 'plano con preinfusio');
      await tester.pumpAndSettle();
      expect(find.text('Plano con preinfusión'), findsOneWidget);
      expect(model.profileSuggestions.first, 'Plano con preinfusión');
      expect(model.draft.profile.text, 'plano con preinfusio');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final fail in [false, true]) {
    test(
      'optional suggestions ${fail ? 'failure' : 'late completion'} preserves text and saving',
      () async {
        final repo = _DelayedProfiles(db);
        final model = BrewFormModel(
          services: AppServices.forJournal(
            repo,
            parameterSettings: BrewParameterSettings(db),
          ),

          coffees: await repo.allCoffees(),
          initialCoffeeId: coffee,
          initialMethodId: method,
        );
        try {
          for (var i = 0; i < 500 && model.busy; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(model.busy, isFalse);
          model.draft.profile.text = 'Manual';
          model.draft.dose.text = '18';
          if (fail) {
            repo.result.completeError(StateError('Suggestions unavailable'));
          } else {
            repo.result.complete(await repository.profileSuggestions());
          }
          await Future<void>.delayed(Duration.zero);
          expect(model.draft.profile.text, 'Manual');
          expect(model.busy, isFalse);
          final saved = await model.save();
          expect(saved, isNotNull);
          expect((await repo.brew(saved!.id))!.profileName, 'Manual');
        } finally {
          model.dispose();
        }
      },
    );
  }

  test('completion after dispose does not notify', () async {
    final repo = _DelayedProfiles(db);
    final model = BrewFormModel(
      services: AppServices.forJournal(
        repo,
        parameterSettings: BrewParameterSettings(db),
      ),

      coffees: await repo.allCoffees(),
      initialCoffeeId: coffee,
    );
    var notified = false;
    model.addListener(() => notified = true);
    model.dispose();
    repo.result.complete(ProfileSuggestions([]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notified, isFalse);
  });
}
