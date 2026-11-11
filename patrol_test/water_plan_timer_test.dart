import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../test/helpers/fake_scale.dart';
import 'support/smoke_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    patrolTest(
      'water plan timer stays with its table in $language',
      tags: ['android', 'water-plan-timer'],
      ($) async {
        final db = await openTestDatabase();
        final scale = FakeScale(name: 'Test scale')..heldOff = true;
        try {
          $.tester.platformDispatcher.platformBrightnessTestValue =
              language == 'es' ? Brightness.dark : Brightness.light;
          await clearTestData(db);
          final repo = JournalRepository(db);
          await repo.createCoffee(
            name: 'Kenya Ruby · Natural',
            roaster: 'Test',
            initialGrams: 250,
          );
          await repo.createMethod(name: 'V60', category: 'pourover');
          await $.pumpWidgetAndSettle(
            HolyBeansApp(
              services: AppServices(database: db, scale: scale),
              initialLocale: Locale(language),
            ),
          );
          final s = lookupAppLocalizations(Locale(language));
          await $.tap(find.text(s.actionBrew));
          await $.waitUntilVisible(find.byType(BrewForm));
          final form = verticalScrollable(find.byType(BrewForm));
          final method = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == s.selectMethod,
          );
          await $.scrollUntilVisible(finder: method, view: form);
          await $.tap(method);
          await $.tap(find.text('V60').last);
          for (final (label, value) in [
            ('${s.dose} (g)', '17.2'),
            ('${s.water} (g)', '275.2'),
          ]) {
            final field = find.widgetWithText(TextFormField, label);
            await $.scrollUntilVisible(finder: field, view: form);
            await $.enterText(field, value);
          }
          for (final (label, value) in [
            (s.bloomCount, '1'),
            (s.pourCount, '2'),
          ]) {
            final field = find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<int> &&
                  w.decoration.labelText == label,
            );
            await $.scrollUntilVisible(finder: field, view: form);
            await $.tap(field);
            await $.tap(find.text(value).last);
          }
          final title = find.textContaining('${s.waterPlanTitle} ·');
          await $.scrollUntilVisible(finder: title, view: form);
          await $.tap(title);
          final toggle = find.byKey(const ValueKey('water-plan-timer-toggle'));
          await $.scrollUntilVisible(finder: toggle, view: form);
          await $.takeNativeScreenshot('water-plan-ready-$language');
          await $.tap(toggle);
          await Future<void>.delayed(const Duration(seconds: 3));
          await $.pumpAndSettle();
          final viewport = $.tester.getRect(form);
          final table = $.tester.getRect(
            find.byKey(const ValueKey('water-plan-table')),
          );
          final clock = $.tester.getRect(
            find.byKey(const ValueKey('water-plan-time')),
          );
          expect(table.bottom, lessThan(viewport.bottom));
          expect(clock.top, greaterThan(viewport.top));
          expect(toggle.hitTestable(), findsOneWidget);
          await $.takeNativeScreenshot('water-plan-running-$language');
          await $.tap(find.byKey(const ValueKey('water-plan-mark-bloom')));
          final model = $.tester
              .widget<BrewPoursSection>(find.byType(BrewPoursSection))
              .model;
          expect(int.parse(model.draft.bloom.text), greaterThanOrEqualTo(3));
          await $.tap(toggle);
          final stoppedAt = model.timer.elapsedSeconds;
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(model.timer.elapsedSeconds, stoppedAt);
          await $.tap(toggle);
          await Future<void>.delayed(const Duration(seconds: 1));
          await $.pumpAndSettle();
          expect(model.timer.elapsedSeconds, greaterThan(stoppedAt));
          await $.tap(toggle);
          await $.scrollUntilVisible(
            finder: title,
            view: form,
            scrollDirection: AxisDirection.up,
          );
          await $.tap(title);
          expect(
            find.byKey(const ValueKey('extraction-timer')),
            findsOneWidget,
          );
          await $.tap(title);
          await scale.connect();
          await $.pumpAndSettle();
          expect(toggle, findsNothing);
          model.timer.reset();
          final chartToggle = find.byKey(const ValueKey('chart-timer-toggle'));
          await $.scrollUntilVisible(finder: chartToggle, view: form);
          await $.tap(chartToggle);
          for (final (index, (grams, flow)) in [
            (0.0, 0.0),
            (10.0, 5.0),
            (25.0, 9.0),
            (34.4, 7.0),
            (34.4, 0.0),
            (34.4, 0.0),
            (34.4, 0.0),
            (50.0, 5.0),
            (80.0, 9.0),
            (110.0, 6.0),
          ].indexed) {
            scale.emit(
              grams,
              flow: flow,
              timerMs: index * 500,
              timerRunning: true,
            );
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          await $.pumpAndSettle();
          expect(model.timer.running, isTrue);
          await $.takeNativeScreenshot('water-plan-chart-$language');
          await $.tap(chartToggle);
          expect(await repo.allBrews(), isEmpty);
          await scale.disconnect();
          await $.pumpAndSettle();
          expect(toggle, findsOneWidget);
          expect(chartToggle, findsNothing);
        } finally {
          await $.pumpWidgetAndSettle(const SizedBox.shrink());
          $.tester.platformDispatcher.clearPlatformBrightnessTestValue();
          scale.dispose();
          await db.close();
        }
      },
    );
  }
}
