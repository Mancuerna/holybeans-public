import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/water_target_settings.dart';
import 'package:holybeans/domain/bloom_water_ratio.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/filter_water_targets.dart';
import 'package:holybeans/ui/brews/weight_targets.dart';

class _MemorySettings extends WaterTargetSettings {
  _MemorySettings() : super(File('unused'));
  bool value = true;
  @override
  Future<bool> load() async => value;
  @override
  Future<void> save(bool visible) async {
    value = visible;
  }
}

class _RecordingCanvas extends Fake implements Canvas {
  final labels = <Rect>[];
  final operations = <String>[];
  final backgrounds = <Color>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    labels.add(rect);
    backgrounds.add(paint.color);
    operations.add('label background');
  }

  @override
  void drawPath(Path path, Paint paint) => operations.add('curve');

  @override
  void drawCircle(Offset center, double radius, Paint paint) {}

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {}

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {}
}

void main() {
  testWidgets('target labels cover crossing curves with opaque backgrounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExtractionChart(
            curve: ShotCurve(
              timesMs: const [0, 5000, 10000],
              weight: const [0, 150, 300],
              flow: const [0, 10, 0],
            ),
            weightTargets: const [
              WeightTarget(grams: 150, label: 'Pour 1 · 150 g', active: true),
              WeightTarget(grams: 300, label: 'Pour 2 · 300 g'),
            ],
            replayable: false,
          ),
        ),
      ),
    );
    final chart = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_ChartPainter',
    );
    final painter = tester.widget<CustomPaint>(chart).painter!;
    final canvas = _RecordingCanvas();
    painter.paint(canvas, const Size(320, 180));
    expect(canvas.labels, hasLength(2));
    expect(
      canvas.operations.indexOf('label background'),
      greaterThan(canvas.operations.lastIndexOf('curve')),
    );
    expect(canvas.backgrounds.every((color) => color.a == 1), isTrue);
  });

  test(
    'bloom ratio is added water per dose and rejects missing or invalid input',
    () {
      expect(bloomWaterRatio(90, 18), 5);
      expect(bloomWaterRatio(45, 18), 2.5);
      for (final values in [
        (null, 18.0),
        (90.0, null),
        (90.0, 0.0),
        (-1.0, 18.0),
        (double.nan, 18.0),
        (90.0, double.infinity),
      ]) {
        expect(bloomWaterRatio(values.$1, values.$2), isNull);
      }
    },
  );
  test(
    'local display choice survives reopening and tolerates damaged storage',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'water-target-settings-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/targets.json');
      final settings = WaterTargetSettings(file);
      expect(await settings.load(), isTrue);
      await settings.save(false);
      expect(await WaterTargetSettings(file).load(), isFalse);
      await file.writeAsString('{invalid');
      expect(await settings.load(), isTrue);
      await settings.save(true);
      expect(await settings.load(), isTrue);
    },
  );
  test('planning stays separate from measured pours and updates cumulative targets', () {
    final draft = BrewPoursDraft()
      ..bloomCount = 1
      ..pourCount = 3;
    addTearDown(draft.dispose);
    var notifications = 0;
    draft.addListener(() => notifications++);
    draft.expandWaterPlan(true);
    draft.expandWaterPlan(false);
    draft.setWaterPlanBloomRatio(5);
    expect(draft.waterPlanUsed, isTrue);
    expect(notifications, 3);
    expect(
      draft.waterPlan(dose: 18, water: 300)!.steps.map((s) => s.targetGrams),
      [90, 160, 230, 300],
    );
    expect(draft.waterPlan(dose: 20, water: 300)!.steps.first.targetGrams, 100);
    expect(
      draft.waterPlan(dose: 18, water: 80)!.problem,
      PourPlanProblem.bloomWater,
    );
    expect(draft.value.phases, isEmpty);
  });
  testWidgets(
    'stored bloom shows its calculated ratio without changing the record',
    (tester) async {
      final pours = BrewPours(
        bloomCount: 1,
        pourCount: 0,
        phases: const [
          BrewPourPhase(kind: BrewPourKind.bloom, number: 1, waterGrams: 90),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: BrewPourDetails(pours: pours, doseGrams: 18)),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('brew-recorded-pour-details')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ratio del bloom: 1:5'), findsOneWidget);
      expect(pours.phases.single.waterGrams, 90);
    },
  );
  testWidgets(
    'toggle removes only guides, remembers choice and follows changed plans',
    (tester) async {
      final settings = _MemorySettings();
      final curve = ShotCurve(
        timesMs: const [0, 1000],
        weight: const [0, 122],
        flow: const [],
      );
      Widget page(double dose, {Key? key}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: FilterWaterTargets(
              key: key,
              plan: PourPlan(
                doseGrams: dose,
                ratio: 300 / dose,
                blooms: const [BloomStep(doseMultiple: 5, waitSeconds: 45)],
              ),
              poured: 122,
              openSettings: () async => settings,
              builder: (targets) => ExtractionChart(
                curve: curve,
                weightTargets: targets,
                showReadout: false,
                replayable: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(18));
      await tester.pumpAndSettle();
      ExtractionChart chart() =>
          tester.widget<ExtractionChart>(find.byType(ExtractionChart));
      expect(chart().weightTargets.map((t) => t.grams), [90, 160, 230, 300]);
      expect(chart().weightTargets.singleWhere((t) => t.active).grams, 160);
      await tester.tap(find.byKey(const ValueKey('water-targets-toggle')));
      await tester.pumpAndSettle();
      expect(chart().weightTargets, isEmpty);
      expect(chart().curve, same(curve));
      expect(settings.value, isFalse);
      await tester.pumpWidget(page(20, key: const ValueKey('reopened')));
      await tester.pumpAndSettle();
      expect(chart().weightTargets, isEmpty);
      await tester.tap(find.byKey(const ValueKey('water-targets-toggle')));
      await tester.pumpAndSettle();
      expect(chart().weightTargets.first.grams, 100);
      expect(tester.takeException(), isNull);
    },
  );

  test('every planned target label is painted without overlap', () {
    final canvas = _RecordingCanvas();
    final targets = [
      for (final grams in [30.0, 60.0, 120.0, 180.0, 240.0])
        WeightTarget(grams: grams, label: '$grams g'),
    ];
    paintWeightTargets(
      canvas,
      const Rect.fromLTRB(0, 0, 300, 60),
      targets,
      (grams) => 60 - grams / 4,
      const TextStyle(fontSize: 11, color: Color(0xFF000000)),
      const Color(0xFF000000),
      const Color(0xFF000000),
      const Color(0xFFFFFFFF),
    );
    expect(canvas.labels, hasLength(targets.length));
    for (var i = 1; i < canvas.labels.length; i++) {
      expect(canvas.labels[i - 1].overlaps(canvas.labels[i]), isFalse);
    }
  });
}
