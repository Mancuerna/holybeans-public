import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    patrolTest(
      'profile suggestions stay editable and save in $language',
      tags: ['android', 'profile-suggestions'],
      ($) async {
        final db = await openTestDatabase();
        try {
          $.tester.platformDispatcher.platformBrightnessTestValue =
              language == 'es' ? Brightness.dark : Brightness.light;
          await clearTestData(db);
          final repo = JournalRepository(db);
          final coffee = await repo.createCoffee(
            name: 'Profile beans',
            roaster: 'Test',
            initialGrams: 250,
          );
          final method = await repo.createMethod(
            name: 'Classic',
            category: 'espresso',
          );
          final other = await repo.createMethod(
            name: 'Lever',
            category: 'espresso',
          );
          for (final (id, name, profile, date) in [
            (method, 'Classic', 'Plano sin preinfusión', DateTime(2026)),
            (other, 'Lever', 'Plano con preinfusión', DateTime(2026, 2)),
          ]) {
            await repo.createBrew(
              coffeeId: coffee,
              methodId: id,
              methodName: name,
              profileName: profile,
              doseGrams: 18,
              temperatureC: 93,
              brewedAt: date,
            );
          }
          await $.pumpWidgetAndSettle(
            HolyBeansApp(
              services: AppServices(database: db),
              initialLocale: Locale(language),
            ),
          );
          final s = lookupAppLocalizations(Locale(language));
          await $.tap(find.text(s.actionBrew));
          await $.waitUntilVisible(find.byType(BrewForm));
          final form = verticalScrollable(find.byType(BrewForm));
          final selector = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == s.selectMethod,
          );
          await $.scrollUntilVisible(finder: selector, view: form);
          await $.tap(selector);
          await $.tap(find.text('Classic').last);
          final profile = find.byKey(const ValueKey('brew-profile'));
          await $.scrollUntilVisible(finder: profile, view: form);
          await $.tap(profile);
          // Native keyboard animation can outlive Flutter's settled frames.
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await $.pumpAndSettle();
          await $.tester.enterText(profile, 'pla');
          await $.pumpAndSettle();
          final first = find.text('Plano sin preinfusión').last;
          final second = find.text('Plano con preinfusión').last;
          expect(
            $.tester.getTopLeft(first).dy,
            lessThan($.tester.getTopLeft(second).dy),
          );
          await $.takeNativeScreenshot('profile-options-$language');
          final keyboardTop =
              MediaQuery.of($.tester.element(profile)).size.height -
              MediaQuery.of($.tester.element(profile)).viewInsets.bottom;
          expect($.tester.getBottomRight(second).dy, lessThan(keyboardTop));
          expect(second.hitTestable(), findsOneWidget);
          await $.tap(second);
          expect(
            $.tester.widget<TextFormField>(profile).controller!.text,
            'Plano con preinfusión',
          );
          await $.tap(profile);
          await $.tester.enterText(profile, 'pla');
          await $.pumpAndSettle();
          await $.tap(first);
          final model = $.tester
              .widget<BrewChoiceSection>(find.byType(BrewChoiceSection))
              .model;
          expect(model.draft.profile.text, 'Plano sin preinfusión');
          expect(model.draft.dose.text, '18');
          expect(model.draft.temperature.text, '93');
          await $.enterText(profile, 'Plano sin preinfusión suave');
          await $.tap(find.text(s.save).last);
          await $.waitUntilVisible(find.text(s.actionBrew));
          final saved = (await repo.allBrews()).singleWhere(
            (b) => b.profileName == 'Plano sin preinfusión suave',
          );
          expect(saved.doseGrams, 18);
          expect(saved.temperatureC, 93);
          await $.tap(find.text(s.actionBrew));
          await $.waitUntilVisible(find.byType(BrewForm));
          await $.scrollUntilVisible(finder: selector, view: form);
          await $.tap(selector);
          await $.tap(find.text('Classic').last);
          await $.scrollUntilVisible(finder: profile, view: form);
          await $.tap(profile);
          await $.tester.enterText(profile, 'plano sin preinfusio');
          await $.pumpAndSettle();
          await $.tap(find.text('Plano sin preinfusión suave').last);
          await $.takeNativeScreenshot('profile-reused-$language');
          await $.tap(find.text(s.cancel).last);
          expect(await repo.allBrews(), hasLength(3));
        } finally {
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          $.tester.platformDispatcher.clearPlatformBrightnessTestValue();
          await db.close();
        }
      },
    );
  }
}
