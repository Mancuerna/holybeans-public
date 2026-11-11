part of '../journal_repository.dart';

extension CoffeeOperations on JournalRepository {
  Future<Coffee?> coffee(String id) => records.coffee(id);

  /// Deletes an unused coffee and its inventory, origins and photo references.
  /// Checks all brews again inside the transaction, archived ones included.
  /// Returns photo files no longer referenced by any coffee or brew.
  Future<List<String>> deleteUnusedCoffee(String id) =>
      coffees.deleteUnusedCoffee(id);
  Future<List<CoffeeLot>> coffeeLots(String coffeeId) =>
      records.coffeeLots(coffeeId);
  Future<CoffeeLot?> coffeeLot(String lotId) => records.coffeeLot(lotId);
  Future<List<CoffeeComponent>> coffeeComponents(String coffeeId) =>
      records.coffeeComponents(coffeeId);

  /// Returns the signed balance across known active lots, or null if any lot
  /// has unknown stock (or no active inventory has been recorded).
  Future<double?> coffeeStockBalance(String coffeeId) =>
      stock.coffeeStockBalance(coffeeId);
  Future<String> createCoffee({
    required String name,
    required String roaster,
    String? country,
    String? region,
    String? farm,
    String? producer,
    String? variety,
    String? process,
    int? altitudeMeters,
    int? altitudeMaxMeters,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
  }) => coffees.createCoffee(
    name: name,
    roaster: roaster,
    country: country,
    region: region,
    farm: farm,
    producer: producer,
    variety: variety,
    process: process,
    altitudeMeters: altitudeMeters,
    altitudeMaxMeters: altitudeMaxMeters,
    roastDate: roastDate,
    initialGrams: initialGrams,
    paidPriceCents: paidPriceCents,
    notes: notes,
    roastLevel: roastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
  );

  /// Creates a coffee with an ordered list of origins, suitable for blends.
  /// An empty list is allowed for coffees whose origin is not recorded yet.
  /// Creates a coffee and, when [freeze] is given, freezes part or all of its
  /// purchased quantity in the same transaction.
  Future<String> createCoffeeWithComponents({
    required String name,
    required String roaster,
    required List<CoffeeComponentInput> components,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
    FreezeRequest? freeze,
    bool isDecaf = false,
    String? shopUrl,
    List<String>? photos,
  }) => coffees.createCoffeeWithComponents(
    name: name,
    roaster: roaster,
    components: components,
    roastDate: roastDate,
    initialGrams: initialGrams,
    paidPriceCents: paidPriceCents,
    notes: notes,
    roastLevel: roastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
    freeze: freeze,
    isDecaf: isDecaf,
    shopUrl: shopUrl,
    photos: photos,
  );
  Future<({String id, String? frozenLabel})> createCoffeeEntry({
    required String name,
    required String roaster,
    required List<CoffeeComponentInput> components,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
    FreezeRequest? freeze,
    bool isDecaf = false,
    String? shopUrl,
    List<String>? photos,
  }) => coffees.createCoffeeEntry(
    name: name,
    roaster: roaster,
    components: components,
    roastDate: roastDate,
    initialGrams: initialGrams,
    paidPriceCents: paidPriceCents,
    notes: notes,
    roastLevel: roastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
    freeze: freeze,
    isDecaf: isDecaf,
    shopUrl: shopUrl,
    photos: photos,
  );
  Future<void> updateCoffee({
    required String id,
    required String name,
    required String roaster,
    String? notes,
  }) =>
      coffees.updateCoffee(id: id, name: name, roaster: roaster, notes: notes);
  Future<void> updateCoffeeProfile({
    required String id,
    required String name,
    required String roaster,
    String? notes,
    String? country,
    String? region,
    String? farm,
    String? producer,
    String? variety,
    String? process,
    int? altitudeMeters,
    int? altitudeMaxMeters,
    required int? paidPriceCents,
    String? roastLevel,
    bool updateRoastLevel = false,
    String? flavorProfile,
    int? restDays,
    bool updateFlavorProfile = false,
    bool updateRestDays = false,
    String? inventoryLotId,
    bool createInventoryLot = false,
    String? roastDate,
    double? initialGrams,
    double? remainingGrams,
    bool updateRemainingStock = false,
    bool updateOrigin = true,
    List<CoffeeComponentInput>? originComponents,
  }) => coffees.updateCoffeeProfile(
    id: id,
    name: name,
    roaster: roaster,
    notes: notes,
    country: country,
    region: region,
    farm: farm,
    producer: producer,
    variety: variety,
    process: process,
    altitudeMeters: altitudeMeters,
    altitudeMaxMeters: altitudeMaxMeters,
    paidPriceCents: paidPriceCents,
    roastLevel: roastLevel,
    updateRoastLevel: updateRoastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
    updateFlavorProfile: updateFlavorProfile,
    updateRestDays: updateRestDays,
    inventoryLotId: inventoryLotId,
    createInventoryLot: createInventoryLot,
    roastDate: roastDate,
    initialGrams: initialGrams,
    remainingGrams: remainingGrams,
    updateRemainingStock: updateRemainingStock,
    updateOrigin: updateOrigin,
    originComponents: originComponents,
  );

  /// Atomically updates a coffee profile and replaces its ordered origins.
  /// Pass an empty [components] list to remove all saved origins.
  Future<void> updateCoffeeProfileWithComponents({
    required String id,
    required String name,
    required String roaster,
    required int? paidPriceCents,
    required List<CoffeeComponentInput> components,
    String? notes,
    String? roastLevel,
    bool updateRoastLevel = false,
    String? flavorProfile,
    int? restDays,
    bool updateFlavorProfile = false,
    bool updateRestDays = false,
    String? inventoryLotId,
    bool createInventoryLot = false,
    String? roastDate,
    double? initialGrams,
    double? remainingGrams,
    bool updateRemainingStock = false,
    bool? isDecaf,
    String? shopUrl,
    List<String>? photos,
  }) => coffees.updateCoffeeProfileWithComponents(
    id: id,
    name: name,
    roaster: roaster,
    paidPriceCents: paidPriceCents,
    components: components,
    notes: notes,
    roastLevel: roastLevel,
    updateRoastLevel: updateRoastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
    updateFlavorProfile: updateFlavorProfile,
    updateRestDays: updateRestDays,
    inventoryLotId: inventoryLotId,
    createInventoryLot: createInventoryLot,
    roastDate: roastDate,
    initialGrams: initialGrams,
    remainingGrams: remainingGrams,
    updateRemainingStock: updateRemainingStock,
    isDecaf: isDecaf,
    shopUrl: shopUrl,
    photos: photos,
  );
  Future<void> setCoffeeArchived(
    String id, {
    required bool archived,
    double? rating,
  }) => coffees.setCoffeeArchived(id, archived: archived, rating: rating);
  Future<void> setCoffeeFavorite(String id, {required bool favorite}) =>
      coffees.setCoffeeFavorite(id, favorite: favorite);
}
