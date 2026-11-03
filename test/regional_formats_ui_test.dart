import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_fields.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_profile_card.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  for (final region in [const Locale('es', 'ES'), const Locale('en', 'US')]) {
    testWidgets('numeric fields follow $region despite the app language', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localeTestValue = region;
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      final comma = region.languageCode == 'es';
      final controller = TextEditingController(text: fieldExact(17.123456789));
      addTearDown(controller.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(comma ? 'en' : 'es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Builder(
                      builder: (context) =>
                          numberField(context, controller, 'Dose'),
                    ),
                    WaterProfileCard(
                      profile: const WaterProfile(
                        id: 'water',
                        name: 'Water',
                        ghPpmAsCaCO3: 87.354,
                      ),
                      onEdit: () {},
                      onArchive: () {},
                      onCalculate: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(controller.text, comma ? '17,123456789' : '17.123456789');
      expect(parseNumber(controller.text), 17.123456789);
      expect(find.text(comma ? '87,35' : '87.35'), findsOneWidget);
      for (final input in ['18.25', '18,25']) {
        await tester.enterText(find.byType(TextFormField), input);
        expect(controller.text, comma ? '18,25' : '18.25');
        expect(parseNumber(controller.text), 18.25);
        expect(form.currentState!.validate(), isTrue);
      }
      await tester.enterText(find.byType(TextFormField), '1,234.5');
      expect(form.currentState!.validate(), isFalse);
      final model = WaterCalculatorModel(
        initialWater: const WaterProfile(
          id: 'w',
          name: 'Water',
          ph: 7.123456789,
          calciumPpm: 12.3456789,
        ),
      );
      addTearDown(model.dispose);
      expect(fieldExact(7.123456789), comma ? '7,123456789' : '7.123456789');
      expect(model.baseGh.text, isEmpty);
      expect(
        model.ions.values.map((c) => c.text),
        contains(comma ? '12,3456789' : '12.3456789'),
      );
    });
  }

  testWidgets(
    'regional decimal symbols and digits can be saved without grouping ambiguity',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'ar',
        'EG',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      expect(parseNumber(fieldNumber(18.25)), 18.25);
      expect(parseNumber(fieldExact(18.123456789)), 18.123456789);
      expect(parseNumber('١٨٫٢٥'), 18.25);
      expect(parsePriceCents('١٨٫٢٥'), 1825);
      expect(parseNumber('1,234.5'), isNull);
    },
  );

  testWidgets('24-hour system preference overrides a US regional clock', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.localeTestValue = const Locale('en', 'US');
    dispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(dispatcher.clearLocaleTestValue);
    addTearDown(dispatcher.clearAlwaysUse24HourTestValue);
    final date = DateTime(2026, 10, 17, 15, 5);
    expect(formatRegionalTime(date, regionalLocale), '15:05');
    expect(formatRegionalDateTime(date, regionalLocale), '10/17/2026 15:05');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: BrewDateTimeChips(value: date, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.text('15:05'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('brew-time-chip')));
    await tester.pumpAndSettle();
    expect(find.text('PM'), findsNothing);
    expect(
      formatRegionalTime(DateTime(2026, 10, 17, 0, 5), regionalLocale),
      '00:05',
    );
    dispatcher.alwaysUse24HourFormatTestValue = false;
    expect(formatRegionalTime(date, regionalLocale), contains('PM'));
    expect(
      formatRegionalTime(DateTime(2026, 10, 17, 0, 5), regionalLocale),
      contains('AM'),
    );
  });
}
