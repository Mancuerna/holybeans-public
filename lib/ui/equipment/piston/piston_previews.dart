import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/piston/piston_credits.dart';

@Preview(name: 'Piston · dark', size: Size(390, 420))
Widget pistonDarkPreview() => _preview(true);
@Preview(name: 'Piston · light', size: Size(390, 420))
Widget pistonLightPreview() => _preview(false);
Widget _preview(bool dark) {
  final start = DateTime(2026).millisecondsSinceEpoch;
  final services = [
    PistonService(
      id: 'example',
      timeMs: start + 45 * Duration.millisecondsPerDay,
      kind: 'grease',
    ),
  ];
  final points = pistonSeries([
    for (var i = 0; i < 90; i++)
      PistonReading(
        shotId: '$i',
        timeMs: start + i * Duration.millisecondsPerDay,
        samples: 5,
        current: 1 + (i % 45) * .01,
        speed: 10,
      ),
  ], services);
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: PistonChart(points: points, services: services, speed: false),
      ),
    ),
  );
}

@Preview(name: 'Piston · credits', size: Size(390, 240))
Widget pistonCreditsPreview() => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(
    body: Padding(padding: EdgeInsets.all(16), child: PistonCredits()),
  ),
);
