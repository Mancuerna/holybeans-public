import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/ui/roasters/roaster_data.dart';
import 'package:holybeans/ui/roasters/roaster_profile_page.dart';
import 'package:holybeans/ui/roasters/roasters_page.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';

void openRoasters(
  BuildContext context,
  JournalViewModel journal,
  JournalActions actions, {
  String? roaster,
}) {
  final cafes = journal.repository.cafes.watch();
  (JournalData, CafeJournalData?)? revision;
  var profiles = <RoasterProfile>[];
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StreamBuilder<CafeJournalData>(
        stream: cafes,
        builder: (_, snapshot) => ListenableBuilder(
          listenable: journal,
          builder: (context, _) {
            final cafeData = snapshot.data;
            final key = (journal.data, cafeData);
            if (key != revision) {
              profiles = roasterProfiles(
                key.$1,
                cafeDrinks: [
                  if (cafeData != null)
                    for (final drink in cafeData.drinks)
                      if (cafeData.roasterOf(drink) case final roaster?)
                        (
                          id: drink.id,
                          roaster: roaster,
                          cafe: cafeData.cafeOf(drink).name,
                          drinkType: drink.drinkType,
                          origin: drink.originCountry,
                          rating: drink.rating,
                        ),
                ],
              );
              revision = key;
            }
            if (roaster == null) {
              return RoastersPage(
                profiles: profiles,
                onOpen: (name) =>
                    openRoasters(context, journal, actions, roaster: name),
              );
            }
            return RoasterProfilePage(
              name: roaster,
              profile: profiles
                  .where((p) => p.key == roasterKey(roaster))
                  .firstOrNull,
              onOpenCoffee: actions.showCoffeeDetailsById,
            );
          },
        ),
      ),
    ),
  );
}
