import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_profile_card.dart';
import 'package:intl/intl.dart';
import 'package:patrol/patrol.dart';

Future<void> checkWaterCards(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final id = await repo.createWaterProfile(
    name: 'Rao/Perger 2012',
    ghPpmAsCaCO3: 87.354,
    khPpmAsCaCO3: 40.248,
    minerals: const WaterMinerals(
      calcium: 10.833,
      magnesium: 14.643,
      sodium: 9.304,
      chloride: 30.476,
      sulfate: 36.279,
      bicarbonate: 49.073,
    ),
  );
  await repo.createWaterProfile(
    name: 'Watertest',
    ghPpmAsCaCO3: 80,
    khPpmAsCaCO3: 40,
    minerals: const WaterMinerals(
      calcium: 0,
      magnesium: 19.427,
      sodium: 18.376,
      potassium: 0,
      chloride: 0,
      sulfate: 76.784,
      bicarbonate: 48.771,
    ),
  );
  final before = await database.select(database.waterProfiles).get();
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('es')),
  );
  final nav = $.tester.getRect(find.byType(NavigationBar));
  await $.tester.tapAt(Offset(nav.left + nav.width * 3.5 / 4, nav.center.dy));
  await $.pumpAndSettle();
  await $.tap(find.text('Agua'));
  await $.waitUntilVisible(find.text('Rao/Perger 2012'));
  expect(
    find.text(NumberFormat('0.##', regionalLocale.toString()).format(87.354)),
    findsOneWidget,
  );
  expect(
    find.text(NumberFormat('0.##', regionalLocale.toString()).format(40.248)),
    findsOneWidget,
  );
  final card = find.ancestor(
    of: find.text('Rao/Perger 2012'),
    matching: find.byType(WaterProfileCard),
  );
  expect(find.byKey(const ValueKey('water-ion-calcium')), findsNothing);
  await $.takeNativeScreenshot('water-cards-collapsed');
  await $.tap(find.descendant(of: card, matching: find.byType(ExpansionTile)));
  final ca = $.tester.getRect(
    find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('water-ion-calcium')),
    ),
  );
  final mg = $.tester.getRect(
    find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('water-ion-magnesium')),
    ),
  );
  expect(ca.top, mg.top);
  expect(find.descendant(of: card, matching: find.text('—')), findsOneWidget);
  await $.takeNativeScreenshot('water-card-raoperger');
  await $.tap(find.text('Rao/Perger 2012'));
  final gh = find.widgetWithText(TextFormField, 'Dureza GH (ppm como CaCO₃)');
  await $.waitUntilVisible(gh);
  expect(
    $.tester.widget<TextFormField>(gh).controller!.text,
    fieldExact(87.354),
  );
  await $.tap(find.text('Cancelar').last);
  await $.scrollUntilVisible(
    finder: find.text('Watertest'),
    view: find.byType(Scrollable).last,
  );
  await $.tester.ensureVisible(
    find.ancestor(
      of: find.text('Watertest'),
      matching: find.byType(WaterProfileCard),
    ),
  );
  await $.pumpAndSettle();
  await $.takeNativeScreenshot('water-card-watertest');
  final after = await database.select(database.waterProfiles).get();
  expect(after, before);
  expect(after.singleWhere((p) => p.id == id).potassiumPpm, isNull);
}
