import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:integration_test/integration_test.dart';

/// Frame timings while the keyboard opens and closes over the brew form,
/// with a journal of everyday size behind it. Run in profile mode, keeping
/// the app installed: without `--keep-app-running`, `flutter drive`
/// uninstalls it at the end and the journal on the phone is lost.
///
///     flutter drive --profile --no-dds --keep-app-running \
///       --driver=test_driver/perf_driver.dart \
///       --target=integration_test/keyboard_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('keyboard over the brew form', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    for (var bean = 0; bean < 8; bean++) {
      final coffeeId = await repository.createCoffee(
        name: 'Coffee $bean',
        roaster: 'Roaster',
        roastDate: DateTime.now()
            .subtract(Duration(days: 5 + bean * 4))
            .toIso8601String()
            .substring(0, 10),
        initialGrams: 250,
      );
      for (var cup = 0; cup < 6; cup++) {
        await repository.createBrew(
          coffeeId: coffeeId,
          methodId: methodId,
          methodName: 'V60',
          doseGrams: 15,
          waterGrams: 250,
          timeSeconds: 180,
          brewedAt: DateTime.now().subtract(Duration(hours: bean * 6 + cup)),
        );
      }
    }

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brew').last);
    await tester.pumpAndSettle();
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await tester.scrollUntilVisible(
      dose,
      200,
      scrollable: find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    Future<void> settle() => Future<void>.delayed(const Duration(seconds: 1));
    await binding.watchPerformance(() async {
      for (var round = 0; round < 3; round++) {
        await tester.tap(dose);
        await settle();
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
      }
    }, reportKey: 'keyboard_brew_form');
  });
}
