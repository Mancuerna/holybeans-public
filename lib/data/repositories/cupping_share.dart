import 'package:holybeans/data/database/app_database.dart';

class CuppingShareCup {
  const CuppingShareCup({
    required this.position,
    this.brew,
    this.coffee,
    this.components = const [],
    this.grinder,
    this.water,
  });
  final int position;
  final Brew? brew;
  final Coffee? coffee;
  final List<CoffeeComponent> components;
  final Grinder? grinder;
  final WaterProfile? water;

  String get letter => String.fromCharCode(65 + position);
  List<int?> get scores => [
    brew?.acidity,
    brew?.sweetness,
    brew?.bitterness,
    brew?.body,
    brew?.aftertaste,
  ];
}

class CuppingShareData {
  const CuppingShareData({
    required this.session,
    required this.cups,
    this.blind = false,
  });
  final CuppingSession session;
  final List<CuppingShareCup> cups;
  final bool blind;

  bool get commonRecipe {
    if (cups.any((c) => c.brew == null)) return false;
    final first = cups.first.brew!;
    return cups.every(
      (c) =>
          c.brew!.doseGrams == first.doseGrams &&
          c.brew!.waterGrams == first.waterGrams &&
          c.brew!.temperatureC == first.temperatureC,
    );
  }
}
