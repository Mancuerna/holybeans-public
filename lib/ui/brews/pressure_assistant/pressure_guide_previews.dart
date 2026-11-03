import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';

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
