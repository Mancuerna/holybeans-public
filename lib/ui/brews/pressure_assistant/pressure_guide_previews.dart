import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_readouts.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';
import 'package:holybeans/ui/core/app_theme.dart';

@Preview(name: 'Pressure reference', size: Size(380, 280))
Widget pressureGuidePreview() => MaterialApp(
  home: Scaffold(
    body: PressureGuideChart(
      guide: PressureGuide.fromCurve(
        ShotCurve(
          timesMs: [0, 5000, 9000, 15000, 30000],
          pressure: [0, 2, 9, 9, 5],
          flow: [],
          weight: [],
        ),
      )!,
      elapsedMs: 18000,
      actual: 7,
      trace: const [
        (elapsedMs: 0, bar: 0, breakBefore: true),
        (elapsedMs: 5000, bar: 2.5, breakBefore: false),
        (elapsedMs: 9000, bar: 8, breakBefore: false),
        (elapsedMs: 15000, bar: 8, breakBefore: false),
        (elapsedMs: 18000, bar: 7, breakBefore: false),
      ],
    ),
  ),
);

@Preview(name: 'Flow reference', size: Size(390, 720))
Widget flowGuidePreview() => flowGuideExample();

@Preview(name: 'Flow reference, dark', size: Size(390, 720))
Widget flowGuideDarkPreview() => flowGuideExample(dark: true);

Widget flowGuideExample({bool dark = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('es'),
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) {
      final s = AppLocalizations.of(context);
      final reference = <GuidePoint>[
        (elapsedMs: 500, value: 0, breakBefore: true),
        (elapsedMs: 5000, value: 0, breakBefore: false),
        (elapsedMs: 9000, value: 1.6, breakBefore: false),
        (elapsedMs: 15000, value: 2.0, breakBefore: false),
        (elapsedMs: 22000, value: 2.0, breakBefore: false),
        (elapsedMs: 30000, value: 1.3, breakBefore: false),
      ];
      return Scaffold(
        appBar: AppBar(title: Text(s.flowAssistant)),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Etiopía · Espresso',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                PressureReadouts(
                  target: '2,0',
                  actual: '1,8',
                  unit: 'g/s',
                  actualLabel: s.flowGuideActual,
                  keyPrefix: 'flow',
                ),
                const SizedBox(height: 12),
                Text('${s.pressureGuideAhead}: 2,0 g/s'),
                ShotGuideChart(
                  reference: reference,
                  target: 2,
                  unit: 'g/s',
                  elapsedMs: 18000,
                  actual: 1.8,
                  trace: const [
                    (elapsedMs: 500, value: 0, breakBefore: true),
                    (elapsedMs: 5500, value: 0, breakBefore: false),
                    (elapsedMs: 10000, value: 1.4, breakBefore: false),
                    (elapsedMs: 15000, value: 1.8, breakBefore: false),
                    (elapsedMs: 18000, value: 1.8, breakBefore: false),
                  ],
                ),
                Text(
                  s.flowGuideBelow('0,2'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(s.flowGuideMarkers),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '18,0 s',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.stop),
                  label: Text(s.stopTimer),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ),
);
