import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/equipment/water_profile_card.dart';

@Preview(name: 'Water card · light', size: Size(360, 650))
Widget waterLightPreview() => _preview(false);
@Preview(name: 'Water card · dark', size: Size(360, 650))
Widget waterDarkPreview() => _preview(true);

Widget _preview(bool dark) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: WaterProfileCard(
        profile: const WaterProfile(
          id: 'preview',
          name: 'Rao/Perger 2012',
          ghPpmAsCaCO3: 87.354,
          khPpmAsCaCO3: 40.248,
          calciumPpm: 10.833,
          magnesiumPpm: 14.643,
          sodiumPpm: 9.304,
          chloridePpm: 30.476,
          sulfatePpm: 36.279,
          bicarbonatePpm: 49.073,
        ),
        onEdit: () {},
        onArchive: () {},
        onCalculate: () {},
      ),
    ),
  ),
);
