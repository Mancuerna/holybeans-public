import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/year_review/year_review_card.dart';
import 'package:holybeans/ui/year_review/year_review_story.dart';

@Preview(name: 'Coffee year · cover', size: Size(360, 640))
Widget yearCoverPreview() => yearCardExample(YearStory.intro);

@Preview(name: 'Coffee year · origins', size: Size(360, 640))
Widget yearOriginsPreview() => yearCardExample(YearStory.origins);

@Preview(name: 'Coffee year · ritual', size: Size(360, 640))
Widget yearRitualPreview() => yearCardExample(YearStory.method);

@Preview(name: 'Coffee year · summary', size: Size(360, 640))
Widget yearSummaryPreview() => yearCardExample(YearStory.finalCard);

CoffeeYear sampleCoffeeYear() => CoffeeYear(
  year: 2025,
  now: DateTime(2026),
  brews: [
    for (var i = 0; i < 342; i++)
      (
        id: '$i',
        coffeeId: 'coffee-${i % 24}',
        methodId: i % 5 == 0 ? 'espresso' : 'v60',
        methodName: i % 5 == 0 ? 'Espresso' : 'V60',
        doseGrams: 18.0,
        rating: i == 20 ? 10.0 : null,
        brewedAtMs: DateTime(2025, 1, 1 + i).millisecondsSinceEpoch,
      ),
  ],
  coffees: [
    for (var i = 0; i < 24; i++)
      (
        id: 'coffee-$i',
        name: i == 0 ? 'La Esperanza' : 'Coffee $i',
        roaster: i % 5 == 0 ? 'Nomad' : 'Hola Coffee',
      ),
  ],
  components: [
    for (var i = 0; i < 24; i++)
      (
        coffeeId: 'coffee-$i',
        country: [
          'Colombia',
          'Ethiopia',
          'Kenya',
          'Brazil',
          'Peru',
          'Guatemala',
          'Rwanda',
          'Costa Rica',
        ][i % 8],
      ),
  ],
  methods: const [(id: 'v60', name: 'V60'), (id: 'espresso', name: 'Espresso')],
);

Widget yearCardExample(YearStory story) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('es'),
  theme: ThemeData(fontFamily: 'Plex'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        height: 640,
        child: YearStoryCard(
          year: sampleCoffeeYear(),
          story: story,
          forExport: true,
        ),
      ),
    ),
  ),
);
