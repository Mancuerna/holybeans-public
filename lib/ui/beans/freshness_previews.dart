import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/app_theme.dart';

@Preview(name: 'Roaster rest · light', size: Size(360, 640))
Widget freshnessLightPreview() => _preview(ThemeMode.light);

@Preview(name: 'Roaster rest · dark', size: Size(360, 640))
Widget freshnessDarkPreview() => _preview(ThemeMode.dark);

@Preview(name: 'Roaster rest · large text', size: Size(320, 800))
Widget freshnessLargeTextPreview() => _preview(ThemeMode.light, textScale: 2);

Widget _preview(ThemeMode mode, {double textScale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FreshnessSection(
            freshness: CoffeeFreshness(
              day: 55,
              pausedDays: 0,
              restDays: 60,
              windows: {
                for (final style in BrewStyle.values)
                  style: freshnessWindow(
                    roastLevel: 'light',
                    style: style,
                    restDays: 60,
                  ),
              },
              sweetSpots: const {},
            ),
          ),
        ),
      ),
    ),
  ),
);
