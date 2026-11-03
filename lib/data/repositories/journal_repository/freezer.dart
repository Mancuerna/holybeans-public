part of '../journal_repository.dart';

/// Frozen portions of a lot.
extension FreezerOperations on JournalRepository {
  Stream<List<FrozenPortion>> watchFrozenPortions() =>
      (database.select(database.frozenPortions)..orderBy([
            (portion) => OrderingTerm.desc(portion.frozenDate),
            (portion) => OrderingTerm.desc(portion.createdAtMs),
          ]))
          .watch();

  Future<List<FrozenPortion>> frozenPortionsForLot(String lotId) =>
      (database.select(database.frozenPortions)
            ..where((portion) => portion.lotId.equals(lotId))
            ..orderBy([(portion) => OrderingTerm.asc(portion.createdAtMs)]))
          .get();

  /// Moves [grams] of unfrozen coffee from [lotId] into a new frozen portion
  /// and returns its ID. The lot must have a known balance that covers it.
  Future<String> freezeCoffee({
    required String lotId,
    required double grams,
    required String frozenDate,
    String? container,
    String? notes,
  }) => database.transaction(() async {
    _checkPositiveGrams(grams, 'grams');
    _checkDate(frozenDate);
    _checkContainer(container);
    final lot = await _requireLot(lotId);
    if (lot.archivedAtMs != null) {
      throw StateError('Archived inventory cannot be frozen');
    }
    final fresh = _freshGrams(lot);
    if (fresh == null || grams > fresh + _gramsTolerance) {
      throw StateError('Not enough unfrozen coffee to freeze');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (database.update(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotId))).write(
      CoffeeLotsCompanion(
        remainingGrams: Value(_roundGrams(lot.remainingGrams! - grams)),
        updatedAtMs: Value(now),
      ),
    );
    final id = _uuid.v4();
    await database
        .into(database.frozenPortions)
        .insert(
          FrozenPortion(
            id: id,
            lotId: lotId,
            label: await _uniqueFrozenLabel(),
            container: container,
            frozenDate: frozenDate,
            initialGrams: grams,
            remainingGrams: grams,
            notes: _trimOrNull(notes),
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
    return id;
  });

  /// Freezes all portions atomically, preserving the original single-portion rules.
  Future<List<String>> freezeCoffeePortions({
    required String lotId,
    required List<double> amounts,
    required String frozenDate,
    String? container,
    String? notes,
  }) {
    final weights = List<double>.of(amounts);
    if (weights.isEmpty || weights.length > 501) {
      throw ArgumentError.value(amounts, 'amounts');
    }
    return database.transaction(() async {
      final ids = <String>[];
      for (final grams in weights) {
        ids.add(
          await freezeCoffee(
            lotId: lotId,
            grams: grams,
            frozenDate: frozenDate,
            container: container,
            notes: notes,
          ),
        );
      }
      return ids;
    });
  }

  /// Returns [grams] of a frozen portion to its lot's unfrozen balance.
  Future<void> thawCoffee(
    String portionId,
    double grams,
  ) => database.transaction(() async {
    _checkPositiveGrams(grams, 'grams');
    final portion = await _requirePortion(portionId);
    if (grams > portion.remainingGrams + _gramsTolerance) {
      throw StateError('Cannot thaw more than the frozen amount');
    }
    final lot = await _requireLot(portion.lotId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final left = _roundGrams(
      (portion.remainingGrams - grams).clamp(0, double.infinity),
    );
    await (database.update(
      database.frozenPortions,
    )..where((row) => row.id.equals(portionId))).write(
      FrozenPortionsCompanion(
        remainingGrams: Value(left),
        updatedAtMs: Value(now),
        thawedAtMs: Value(left == 0 ? now : null),
      ),
    );
    // Thawing into a lot with no unfrozen coffee left means the coffee
    // now in use sat in the freezer, so its age pauses for that time.
    final fresh = _freshGrams(lot);
    final frozenOn = DateTime.tryParse(portion.frozenDate);
    final today = DateTime.now();
    final pause = fresh != null && fresh <= _gramsTolerance && frozenOn != null
        ? DateTime.utc(today.year, today.month, today.day)
              .difference(
                DateTime.utc(frozenOn.year, frozenOn.month, frozenOn.day),
              )
              .inDays
        : null;
    await (database.update(
      database.coffeeLots,
    )..where((row) => row.id.equals(lot.id))).write(
      CoffeeLotsCompanion(
        remainingGrams: Value(_roundGrams((lot.remainingGrams ?? 0) + grams)),
        frozenPauseDays: pause == null || pause < 0
            ? const Value.absent()
            : Value(pause),
        updatedAtMs: Value(now),
      ),
    );
  });

  /// Edits a portion. Changing the frozen weight moves the difference between
  /// the portion and its lot, keeping what was already thawed.
  Future<void> updateFrozenPortion({
    required String id,
    required double initialGrams,
    required String frozenDate,
    String? container,
    String? notes,
  }) => database.transaction(() async {
    _checkPositiveGrams(initialGrams, 'initialGrams');
    _checkDate(frozenDate);
    _checkContainer(container);
    final portion = await _requirePortion(id);
    final lot = await _requireLot(portion.lotId);
    final delta = initialGrams - portion.initialGrams;
    final remaining = portion.remainingGrams + delta;
    if (remaining < -_gramsTolerance) {
      throw StateError('Frozen weight cannot be below the thawed amount');
    }
    if (delta > 0) {
      final fresh = _freshGrams(lot);
      if (fresh == null || delta > fresh + _gramsTolerance) {
        throw StateError('Not enough unfrozen coffee to freeze');
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final left = _roundGrams(remaining.clamp(0, double.infinity));
    await (database.update(
      database.frozenPortions,
    )..where((row) => row.id.equals(id))).write(
      FrozenPortionsCompanion(
        initialGrams: Value(initialGrams),
        remainingGrams: Value(left),
        frozenDate: Value(frozenDate),
        container: Value(container),
        notes: Value(_trimOrNull(notes)),
        updatedAtMs: Value(now),
        thawedAtMs: Value(left == 0 ? (portion.thawedAtMs ?? now) : null),
      ),
    );
    if (delta != 0) {
      await (database.update(
        database.coffeeLots,
      )..where((row) => row.id.equals(lot.id))).write(
        CoffeeLotsCompanion(
          remainingGrams: Value(_roundGrams((lot.remainingGrams ?? 0) - delta)),
          updatedAtMs: Value(now),
        ),
      );
    }
  });

  /// Removes a portion recorded by mistake, returning what is still frozen to
  /// the lot's unfrozen balance.
  Future<void> deleteFrozenPortion(String id) => database.transaction(() async {
    final portion = await _requirePortion(id);
    final lot = await _requireLot(portion.lotId);
    if (portion.remainingGrams > 0) {
      await (database.update(
        database.coffeeLots,
      )..where((row) => row.id.equals(lot.id))).write(
        CoffeeLotsCompanion(
          remainingGrams: Value(
            _roundGrams((lot.remainingGrams ?? 0) + portion.remainingGrams),
          ),
          updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
    await (database.update(
      database.brews,
    )..where((row) => row.frozenPortionId.equals(id))).write(
      const BrewsCompanion(
        frozenPortionId: Value(null),
        frozenDoseGrams: Value(null),
      ),
    );
    await (database.delete(
      database.frozenPortions,
    )..where((row) => row.id.equals(id))).go();
  });

  Future<String> _uniqueFrozenLabel() async {
    final used = {
      for (final row in await database.select(database.frozenPortions).get())
        row.label,
    };
    while (true) {
      final label = String.fromCharCodes(
        List.generate(
          5,
          (_) => _labelAlphabet.codeUnitAt(
            _labelRandom.nextInt(_labelAlphabet.length),
          ),
        ),
      );
      if (!used.contains(label)) return label;
    }
  }

  Future<CoffeeLot> _requireLot(String id) async {
    final lot = await (database.select(
      database.coffeeLots,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (lot == null) throw StateError('Inventory record not found');
    return lot;
  }

  Future<FrozenPortion> _requirePortion(String id) async {
    final portion = await (database.select(
      database.frozenPortions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (portion == null) throw StateError('Frozen portion not found');
    return portion;
  }
}
