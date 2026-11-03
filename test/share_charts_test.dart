import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/share_brew_charts.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/app_theme.dart';

void main() {
  testWidgets('missing recordings disable attachments without inventing data', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final coffee = await repo.createCoffee(
      name: 'No readings',
      roaster: 'Fixture',
    );
    final methodId = await repo.createMethod(
      name: 'Custom machine',
      category: 'espresso',
    );
    await repo.createBrew(
      coffeeId: coffee,
      methodId: methodId,
      methodName: 'Custom machine',
      doseGrams: 18,
      beverageGrams: 36,
    );
    final brew = await db.select(db.brews).getSingle();
    final method = await (db.select(
      db.brewMethods,
    )..where((row) => row.id.equals(methodId))).getSingle();
    final data = brewShareChartData(brew, method, null);
    expect(data.espresso, isTrue);
    expect(data.hasMap, isFalse);
    expect(data.hasCurve, isFalse);
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        brewShareChartData(
          brew.copyWith(tdsPercent: Value(value)),
          method,
          null,
        ).hasMap,
        isFalse,
      );
    }
    final oneSample = ShotCurve(timesMs: [0], flow: [], weight: [0]);
    expect(
      brewShareChartData(brew, method, (
        curve: oneSample,
        source: 'scale',
      )).hasCurve,
      isFalse,
    );
    // Valid measurements outside the plotted range still get an explanatory map.
    expect(
      brewShareChartData(
        brew.copyWith(tdsPercent: const Value(30)),
        method,
        null,
      ).hasMap,
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareChartOptions(
            data: data,
            curveSelected: false,
            mapSelected: false,
            onCurveChanged: (_) => fail('Unavailable curve selected'),
            onMapChanged: (_) => fail('Unavailable map selected'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in ['share-include-curve', 'share-include-map']) {
      final finder = find.byKey(ValueKey(key));
      expect(tester.widget<CheckboxListTile>(finder).onChanged, isNull);
      await tester.tap(finder);
    }
    expect(find.text('This brew has no recorded curve.'), findsOneWidget);
    expect(
      find.text('Requires recorded dose, beverage yield and TDS.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  for (final language in ['en', 'es']) {
    for (final espresso in [true, false]) {
      testWidgets(
        'image includes complete charts $language espresso=$espresso',
        (tester) async {
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = JournalRepository(db);
          final id = await repo.createCoffee(
            name: 'Chart coffee',
            roaster: 'Roaster',
          );
          await repo.createBrew(
            coffeeId: id,
            methodName: espresso ? 'Espresso' : 'V60',
            doseGrams: 18,
            beverageGrams: espresso ? 36 : 270,
            tdsPercent: espresso ? 10 : 1.35,
          );
          final coffee = await db.select(db.coffees).getSingle();
          final brew = await db.select(db.brews).getSingle();
          final curve = ShotCurve(
            timesMs: [0, 5000, 15000, 30000],
            pressure: espresso ? [0, 3, 9, 6] : [],
            flow: [0, 1, 2, 1],
            weight: [0, 3, 17, 36],
          );
          final style = espresso
              ? ShareTemplateStyle.espresso
              : ShareTemplateStyle.filter;
          final data = brewShareChartData(brew, null, (
            curve: curve,
            source: 'scale',
          ));
          expect(data.hasMap, isTrue);
          expect(data.hasCurve, isTrue);
          expect(data.espresso, espresso);
          expect(
            brewShareChartData(
              brew.copyWith(tdsPercent: const Value(null)),
              null,
              null,
            ).hasMap,
            isFalse,
          );
          ShareBrewResult? result;
          await tester.pumpWidget(
            MaterialApp(
              theme: language == 'es' ? AppTheme.dark() : AppTheme.light(),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showModalBottomSheet<ShareBrewResult>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ShareBrewSheet(
                          coffee: coffee,
                          brew: brew,
                          components: const [],
                          initialFields: const {BrewParameter.coffee},
                          recording: data.recording,
                          configuration: espresso
                              ? ShareConfiguration(
                                  fields: const {BrewParameter.coffee},
                                  templates: [
                                    ShareTemplate(
                                      id: 't',
                                      name: 'My brew',
                                      style: style,
                                      body: 'My <method>: <ratio>',
                                    ),
                                  ],
                                  defaults: {style: 't'},
                                )
                              : null,
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final s = lookupAppLocalizations(Locale(language));
          expect(find.byKey(const ValueKey('share-include-map')), findsNothing);
          await tester.tap(find.text(s.shareFormatImage));
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('brew-share-card'));
          final initialHeight = tester.getSize(card).height;
          expect(find.byType(ExtractionChart), findsNothing);
          for (final key in ['share-include-curve', 'share-include-map']) {
            final option = find.byKey(ValueKey(key));
            expect(tester.widget<CheckboxListTile>(option).value, isFalse);
            await tester.ensureVisible(option);
            await tester.tap(option);
            await tester.pumpAndSettle();
          }
          expect(
            find.byKey(
              ValueKey(espresso ? 'espresso-map' : 'sensory-map-chart'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              ValueKey(espresso ? 'sensory-map-chart' : 'espresso-map'),
            ),
            findsNothing,
          );
          expect(
            tester
                .widget<ExtractionChart>(find.byType(ExtractionChart))
                .interactive,
            isFalse,
          );
          final height = tester.getSize(card).height;
          expect(height, greaterThan(initialHeight + 400));
          await tester.runAsync(() async {
            await tester.tap(find.byKey(const ValueKey('share-confirm')));
            for (var attempt = 0; result == null && attempt < 100; attempt++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump();
            }
          });
          await tester.pumpAndSettle();
          expect(result, isNotNull);
          expect(result!.rememberFields, !espresso);
          await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(result!.image!);
            final frame = await codec.getNextFrame();
            expect(frame.image.height, closeTo(height * 3, 1));
            expect(frame.image.height, greaterThan(850 * 3));
            frame.image.dispose();
            codec.dispose();
          });
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
