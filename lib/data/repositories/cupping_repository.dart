import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_repository.dart';
import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/data/repositories/equipment_repository.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:uuid/uuid.dart';

class CuppingStockException implements Exception {
  const CuppingStockException(this.coffeeId);
  final String coffeeId;
}

/// Cupping sessions and the brews created when a session is completed.
class CuppingRepository {
  CuppingRepository(
    this.database,
    this._brew,
    this._equipment,
    this._freezer,
    this._records,
  );
  final AppDatabase database;
  final BrewRepository _brew;
  final EquipmentRepository _equipment;
  final FreezerRepository _freezer;
  final JournalRecordQueries _records;
  final Uuid _uuid = const Uuid();

  Future<CuppingShareData> cuppingShareData(String id) => database.transaction(
    () async {
      final session = await cuppingSession(id);
      if (session == null || session.completedAtMs == null) {
        throw StateError('Only completed cupping sessions can be shared');
      }
      final draft = CuppingDraft.fromJson(session.draftJson);
      final count = draft.cups.length;
      final links = await cuppingCups(id);
      final cups = <CuppingShareCup>[];
      for (var position = 0; position < count; position++) {
        final link = links.where((c) => c.position == position).firstOrNull;
        final brew = link == null ? null : await _records.brew(link.brewId);
        cups.add(
          CuppingShareCup(
            position: position,
            brew: brew,
            coffee: brew == null ? null : await _records.coffee(brew.coffeeId),
            components: brew == null
                ? const []
                : await _records.coffeeComponents(brew.coffeeId),
            grinder: brew?.grinderId == null
                ? null
                : await (database.select(database.grinders)
                        ..where((g) => g.id.equals(brew!.grinderId!)))
                      .getSingleOrNull(),
            water: brew?.waterProfileId == null
                ? null
                : await (database.select(database.waterProfiles)
                        ..where((w) => w.id.equals(brew!.waterProfileId!)))
                      .getSingleOrNull(),
          ),
        );
      }
      return CuppingShareData(
        session: session,
        cups: List.unmodifiable(cups),
        blind: draft.blind,
      );
    },
  );

  Future<
    ({
      List<Coffee> coffees,
      List<CoffeeLot> lots,
      List<FrozenPortion> portions,
      List<Grinder> grinders,
      List<WaterProfile> waters,
    })
  >
  cuppingCatalog() => database.transaction(
    () async => (
      coffees: await database.select(database.coffees).get(),
      lots: await database.select(database.coffeeLots).get(),
      portions: await database.select(database.frozenPortions).get(),
      grinders: await database.select(database.grinders).get(),
      waters: await database.select(database.waterProfiles).get(),
    ),
  );

  Stream<List<CuppingSession>> watchCuppingSessions() => (database.select(
    database.cuppingSessions,
  )..orderBy([(s) => OrderingTerm.desc(s.createdAtMs)])).watch();

  Future<CuppingSession?> cuppingSession(String id) => (database.select(
    database.cuppingSessions,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<CuppingSessionCup>> cuppingCups(String id) =>
      (database.select(database.cuppingSessionCups)
            ..where((c) => c.sessionId.equals(id))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .get();

  Future<String> createCuppingSession(CuppingDraft draft) async {
    final json = draft.toJson();
    CuppingDraft.fromJson(json);
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await database
        .into(database.cuppingSessions)
        .insert(
          CuppingSessionsCompanion.insert(
            id: id,
            name: draft.name.trim(),
            draftJson: json,
            startedAtMs: Value(draft.startedAtMs),
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
    return id;
  }

  Future<void> saveCuppingDraft(String id, CuppingDraft draft) =>
      database.transaction(() async {
        final json = draft.toJson();
        final snapshot = CuppingDraft.fromJson(json);
        final session = await cuppingSession(id);
        if (session == null ||
            session.completedAtMs != null ||
            !snapshot.preservesBlindResults(
              CuppingDraft.fromJson(session.draftJson),
            )) {
          throw StateError('Cupping draft is not editable');
        }
        final changed =
            await (database.update(
              database.cuppingSessions,
            )..where((s) => s.id.equals(id) & s.completedAtMs.isNull())).write(
              CuppingSessionsCompanion(
                name: Value(draft.name.trim()),
                draftJson: Value(json),
                startedAtMs: Value(draft.startedAtMs),
                updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );
        if (changed != 1) throw StateError('Cupping draft is not editable');
      });

  /// Discards only an unfinished session; no brew or inventory was created.
  Future<void> discardCuppingDraft(String id) async {
    await (database.delete(
      database.cuppingSessions,
    )..where((s) => s.id.equals(id) & s.completedAtMs.isNull())).go();
  }

  /// Finishing is idempotent and atomic, including thawing and repeated cups.
  Future<List<String>> finishCupping(String id, CuppingDraft draft) =>
      database.transaction(() async {
        final session = await cuppingSession(id);
        if (session == null) throw StateError('Cupping session not found');
        if (session.completedAtMs != null) {
          return [for (final c in await cuppingCups(id)) c.brewId];
        }
        final snapshot = CuppingDraft.fromJson(draft.toJson());
        final previous = CuppingDraft.fromJson(session.draftJson);
        if (!snapshot.preservesBlindResults(previous) ||
            (snapshot.blind && !previous.revealed)) {
          throw StateError('Blind cupping results are not confirmed');
        }
        if (!snapshot.ready ||
            snapshot.tastingAtMs == null ||
            snapshot.brokenAtMs == null) {
          throw StateError('Cupping session is incomplete');
        }
        await _validateCuppingStock(snapshot);
        final method = await _cuppingMethod();
        final ids = <String>[];
        for (var position = 0; position < snapshot.cups.length; position++) {
          final cup = snapshot.cups[position];
          final brewId = await _brew.createBrew(
            coffeeId: cup.coffeeId!,
            lotId: cup.lotId,
            methodId: method.id,
            methodName: method.name,
            grinderId: snapshot.grinderFor(cup),
            grindSetting: snapshot.settingFor(cup),
            waterProfileId: snapshot.waterFor(cup),
            doseGrams: snapshot.dose,
            waterGrams: snapshot.water,
            temperatureC: snapshot.temperature,
            rating: cup.rating,
            notes: cup.notes,
            brewedAt: DateTime.fromMillisecondsSinceEpoch(
              snapshot.startedAtMs!,
            ),
            frozenSource: cup.frozenPortionId == null
                ? null
                : FrozenBrewSource(
                    portionId: cup.frozenPortionId!,
                    lotId: cup.lotId!,
                    grams: snapshot.dose,
                  ),
          );
          // The session clock is not an extraction duration.
          await _brew.rateBrew(
            brewId,
            rating: cup.rating,
            notes: cup.notes,
            tasting: BrewTasting(
              acidity: cup.scores[0],
              sweetness: cup.scores[1],
              bitterness: cup.scores[2],
              body: cup.scores[3],
              aftertaste: cup.scores[4],
            ),
          );
          await database
              .into(database.cuppingSessionCups)
              .insert(
                CuppingSessionCupsCompanion.insert(
                  id: _uuid.v4(),
                  sessionId: id,
                  brewId: brewId,
                  position: position,
                ),
              );
          ids.add(brewId);
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        await (database.update(
          database.cuppingSessions,
        )..where((s) => s.id.equals(id))).write(
          CuppingSessionsCompanion(
            name: Value(snapshot.name.trim()),
            draftJson: Value(snapshot.toJson()),
            startedAtMs: Value(snapshot.startedAtMs),
            completedAtMs: Value(now),
            updatedAtMs: Value(now),
          ),
        );
        return ids;
      });

  Future<BrewMethod> _cuppingMethod() async {
    final existing = await (database.select(
      database.brewMethods,
    )..where((m) => m.templateType.equals('cupping'))).get();
    final active = existing.where((m) => m.archivedAtMs == null).firstOrNull;
    if (active != null &&
        active.category == 'immersion' &&
        active.machine == null) {
      return active;
    }
    // A stable marker works across renames/locales. Never repurpose a user's
    // unrelated method named Cupping or silently unarchive a historic method.
    final id = _uuid.v4();
    await database
        .into(database.brewMethods)
        .insert(
          BrewMethodsCompanion.insert(
            id: id,
            name: 'Cupping',
            category: const Value('immersion'),
            templateType: const Value('cupping'),
          ),
        );
    return _equipment.requireMethodRow(id);
  }

  Future<void> validateCuppingSetup(CuppingDraft draft) async {
    final snapshot = CuppingDraft.fromJson(draft.toJson());
    if (!snapshot.recipeValid ||
        (!snapshot.blind && snapshot.cups.any((c) => c.coffeeId == null))) {
      throw StateError('Incomplete cupping setup');
    }
    if (!snapshot.blind) await _validateCuppingStock(snapshot);
    for (final cup in snapshot.cups) {
      if (snapshot.grinderFor(cup) case final id?) {
        await _equipment.requireGrinder(id);
      }
      if (snapshot.waterFor(cup) case final id?) {
        final water = await (database.select(
          database.waterProfiles,
        )..where((w) => w.id.equals(id))).getSingleOrNull();
        if (water == null || water.archivedAtMs != null) {
          throw StateError('Water unavailable');
        }
      }
    }
  }

  Future<void> _validateCuppingStock(CuppingDraft draft) async {
    final fresh = <String, double>{};
    final frozen = <String, double>{};
    for (final cup in draft.cups) {
      final coffee = await _records.coffee(cup.coffeeId!);
      if (coffee == null || coffee.archivedAtMs != null) {
        throw const BrewCoffeeArchivedException();
      }
      final lotId = cup.lotId;
      if (lotId == null) {
        if ((await _records.coffeeLots(coffee.id))
                .any((l) => l.archivedAtMs == null) ||
            cup.frozenPortionId != null) {
          throw StateError('Cupping cup needs an inventory source');
        }
        continue;
      }
      final lot = await (database.select(
        database.coffeeLots,
      )..where((l) => l.id.equals(lotId))).getSingleOrNull();
      if (lot == null ||
          lot.coffeeId != coffee.id ||
          lot.archivedAtMs != null) {
        throw StateError('Invalid cupping inventory');
      }
      final portionId = cup.frozenPortionId;
      if (portionId == null) {
        fresh.update(lotId, (g) => g + draft.dose, ifAbsent: () => draft.dose);
      } else {
        final portion = await _freezer.requirePortion(portionId);
        if (portion.lotId != lotId) throw StateError('Invalid cupping portion');
        frozen.update(
          portionId,
          (g) => g + draft.dose,
          ifAbsent: () => draft.dose,
        );
      }
    }
    for (final entry in fresh.entries) {
      final lot = await (database.select(
        database.coffeeLots,
      )..where((l) => l.id.equals(entry.key))).getSingle();
      final grams = freshStockGrams(lot);
      if (grams != null && grams + stockTolerance < entry.value) {
        throw CuppingStockException(lot.coffeeId);
      }
    }
    for (final entry in frozen.entries) {
      final portion = await _freezer.requirePortion(entry.key);
      if (portion.remainingGrams + stockTolerance < entry.value) {
        final lot = await (database.select(
          database.coffeeLots,
        )..where((l) => l.id.equals(portion.lotId))).getSingle();
        throw CuppingStockException(lot.coffeeId);
      }
    }
  }
}
