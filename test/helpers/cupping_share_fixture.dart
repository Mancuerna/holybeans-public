import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';

Future<CuppingShareData> cuppingShareFixture(
  JournalRepository r, {
  int count = 6,
}) async {
  final coffee = await r.createCoffeeWithComponents(
    name: 'La Esperanza',
    roaster: 'Tostador Norte',
    initialGrams: 250,
    components: const [
      CoffeeComponentInput(country: 'Colombia', process: 'Lavado'),
    ],
  );
  final otherCoffee = await r.createCoffee(
    name: 'Koke',
    roaster: 'Tostador Sur',
  );
  final lot = (await r.coffeeLots(coffee)).single.id;
  final otherLot = (await r.coffeeLots(otherCoffee)).single.id;
  final grinder = await r.createGrinder(name: 'Comandante C40');
  final otherGrinder = await r.createGrinder(name: 'Timemore 064S');
  final water = await r.createWaterProfile(name: 'Agua A');
  final otherWater = await r.createWaterProfile(name: 'Agua B');
  final d =
      CuppingDraft(
          cups: [
            for (var i = 0; i < count; i++)
              CuppingCupDraft(
                  coffeeId: i == 1 ? otherCoffee : coffee,
                  lotId: i == 1 ? otherLot : lot,
                )
                ..rating = i == 0 ? 0 : 8.5
                ..scores = [4, 5, 1, 3, 4]
                ..notes =
                    'Notas ${String.fromCharCode(65 + i)}\nFinal limpio: sin recortes.',
          ],
        )
        ..name = 'Cata de la mañana'
        ..grinderId = grinder
        ..grindSetting = '24 clics'
        ..waterProfileId = water
        ..startedAtMs = DateTime(2026, 10, 9, 9).millisecondsSinceEpoch
        ..brokenAtMs = DateTime(2026, 10, 9, 9, 4).millisecondsSinceEpoch
        ..tastingAtMs = DateTime(2026, 10, 9, 9, 12).millisecondsSinceEpoch
        ..phase = CuppingPhase.tasting;
  d.cups.last
    ..commonWater = false
    ..waterProfileId = otherWater
    ..commonGrinder = false
    ..grinderId = otherGrinder
    ..grindSetting = '5';
  final id = await r.createCuppingSession(d);
  await r.finishCupping(id, d);
  return r.cuppingShareData(id);
}
