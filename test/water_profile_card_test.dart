import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/equipment/water_profile_card.dart';

const rao = WaterProfile(
  id: 'rao',
  name: 'Rao/Perger 2012',
  ghPpmAsCaCO3: 87.354,
  khPpmAsCaCO3: 40.248,
  calciumPpm: 10.833,
  magnesiumPpm: 14.643,
  sodiumPpm: 9.304,
  chloridePpm: 30.476,
  sulfatePpm: 36.279,
  bicarbonatePpm: 49.073,
);

void main() {
  for (final language in ['es', 'en']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'water card keeps aligned readable values at 320px $language $scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var edits = 0;
          var archives = 0;
          var calculations = 0;
          var recipes = 0;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              theme: language == 'es' ? AppTheme.dark() : AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: WaterProfileCard(
                    profile: rao,
                    onEdit: () => edits++,
                    onArchive: () => archives++,
                    onCalculate: () => calculations++,
                    onRecipe: () => recipes++,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final s = lookupAppLocalizations(Locale(language));
          expect(find.text('87.35'), findsOneWidget);
          expect(find.byKey(const ValueKey('water-ion-calcium')), findsNothing);
          final collapsedHeight = tester
              .getSize(find.byType(WaterProfileCard))
              .height;
          await tester.tap(find.text(s.waterCompositionSummary));
          await tester.pumpAndSettle();
          expect(edits, 0);
          expect(
            tester.getSize(find.byType(WaterProfileCard)).height,
            greaterThan(collapsedHeight),
          );
          expect(find.text('14.64'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          expect(find.text(s.waterSummaryMissing), findsOneWidget);
          expect(find.byType(Chip), findsNothing);
          final calcium = tester.getRect(
            find.byKey(const ValueKey('water-ion-calcium')),
          );
          final magnesium = tester.getRect(
            find.byKey(const ValueKey('water-ion-magnesium')),
          );
          expect(tester.getRect(find.text('10.83')).right, calcium.right);
          expect(tester.getRect(find.text('14.64')).right, magnesium.right);
          if (scale == 1) {
            expect(calcium.top, magnesium.top);
            expect(calcium.right, lessThan(magnesium.left));
          } else {
            expect(calcium.bottom, lessThan(magnesium.top));
          }
          expect(
            tester.getRect(find.byTooltip(s.actions)).bottom,
            lessThan(calcium.top),
          );
          await tester.tap(find.text(s.waterCompositionSummary));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('water-ion-calcium')), findsNothing);
          expect(edits, 0);
          await tester.tap(find.text(rao.name));
          expect(edits, 1);
          for (final label in [
            s.editWaterProfile,
            s.waterUseInitial,
            s.waterRecipeOpen,
            s.archiveWaterProfile,
          ]) {
            await tester.tap(find.byTooltip(s.actions));
            await tester.pumpAndSettle();
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
          }
          expect([edits, calculations, recipes, archives], [2, 1, 1, 1]);
          expect(rao.ghPpmAsCaCO3, 87.354);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('two waters fit collapsed and expand independently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              for (final profile in [
                rao,
                rao.copyWith(id: 'second', name: 'Second water'),
              ])
                WaterProfileCard(
                  profile: profile,
                  onEdit: () => edits++,
                  onArchive: () {},
                  onCalculate: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(rao.name).hitTestable(), findsOneWidget);
    expect(find.text('Second water').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('water-ion-calcium')), findsNothing);
    final first = find.byKey(const PageStorageKey('water-composition-rao'));
    final second = find.byKey(const PageStorageKey('water-composition-second'));
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: first,
        matching: find.byKey(const ValueKey('water-ion-calcium')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: second,
        matching: find.byKey(const ValueKey('water-ion-calcium')),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Mineral composition in mg/L').first);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: first,
        matching: find.byKey(const ValueKey('water-ion-calcium')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: second,
        matching: find.byKey(const ValueKey('water-ion-calcium')),
      ),
      findsOneWidget,
    );
    expect(edits, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero minerals stay zero and a name-only profile stays compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              WaterProfileCard(
                profile: const WaterProfile(
                  id: 'zero',
                  name: 'Zero measured',
                  calciumPpm: 0,
                  potassiumPpm: 0,
                ),
                onEdit: () {},
                onArchive: () {},
                onCalculate: () {},
              ),
              WaterProfileCard(
                profile: const WaterProfile(id: 'empty', name: 'Name only'),
                onEdit: () {},
                onArchive: () {},
                onCalculate: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(5));
    expect(find.text('Mineral composition in mg/L'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
