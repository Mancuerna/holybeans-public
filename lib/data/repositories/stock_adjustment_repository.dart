import 'dart:math';

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/coffee_profile_writer.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:uuid/uuid.dart';

class StockAdjustmentException implements Exception {
  const StockAdjustmentException(this.code);
  final String code;
}

/// Explicit inventory corrections and their reversible history.
class StockAdjustmentRepository {
  StockAdjustmentRepository(this.database, this._profile, this._records);
  final AppDatabase database;
  final CoffeeProfileWriter _profile;
  final JournalRecordQueries _records;
  final Uuid _uuid = const Uuid();

  Stream<List<StockAdjustment>> watchStockAdjustments({
    String? coffeeId,
    bool activeOnly = false,
  }) {
    final query = database.select(database.stockAdjustments);
    if (coffeeId != null) query.where((r) => r.coffeeId.equals(coffeeId));
    if (activeOnly) {
      final lots = database.selectOnly(database.coffeeLots)
        ..addColumns([database.coffeeLots.id])
        ..where(database.coffeeLots.archivedAtMs.isNull());
      query.where((r) => r.reversedAtMs.isNull() & r.lotId.isInQuery(lots));
    }
    query.orderBy([
      (r) => OrderingTerm.desc(r.createdAtMs),
      (r) => OrderingTerm.asc(r.id),
    ]);
    return query.watch();
  }

  Future<List<StockAdjustment>> stockAdjustments(String coffeeId) =>
      (database.select(database.stockAdjustments)
            ..where((r) => r.coffeeId.equals(coffeeId))
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAtMs),
              (r) => OrderingTerm.asc(r.id),
            ]))
          .get();

  Future<String> adjustStock({
    required String coffeeId,
    required String reason,
    required double grams,
    String? frozenPortionId,
    String? notes,
  }) => database.transaction(() async {
    if (!{'gift', 'waste', 'correction'}.contains(reason) ||
        !grams.isFinite ||
        grams < 0 ||
        (reason != 'correction' && grams == 0) ||
        (notes?.length ?? 0) > 500) {
      throw const StockAdjustmentException('invalid');
    }
    final owner = await _records.coffee(coffeeId);
    if (owner == null || owner.archivedAtMs != null) {
      throw const StockAdjustmentException('archived');
    }
    final operation = _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    Future<void> record(
      CoffeeLot lot,
      double? before,
      double after,
      String? portion, {
      bool keepUnchanged = false,
    }) async {
      if (!keepUnchanged &&
          before != null &&
          (before - after).abs() < stockTolerance) {
        return;
      }
      await database
          .into(database.stockAdjustments)
          .insert(
            StockAdjustment(
              id: _uuid.v4(),
              operationId: operation,
              coffeeId: coffeeId,
              lotId: lot.id,
              frozenPortionId: portion,
              reason: reason,
              previousGrams: before,
              resultingGrams: after,
              notes: trimOrNull(notes),
              createdAtMs: now,
            ),
          );
      if (portion == null) {
        final (remaining, overdraw) = materializeBalance(after);
        await (database.update(
          database.coffeeLots,
        )..where((r) => r.id.equals(lot.id))).write(
          CoffeeLotsCompanion(
            remainingGrams: Value(remaining),
            overdrawGrams: Value(overdraw),
            updatedAtMs: Value(now),
          ),
        );
      } else {
        await (database.update(
          database.frozenPortions,
        )..where((r) => r.id.equals(portion))).write(
          FrozenPortionsCompanion(
            remainingGrams: Value(after),
            thawedAtMs: Value(after <= stockTolerance ? now : null),
            updatedAtMs: Value(now),
          ),
        );
      }
    }

    if (frozenPortionId != null) {
      final portion = await (database.select(
        database.frozenPortions,
      )..where((r) => r.id.equals(frozenPortionId))).getSingleOrNull();
      final lot = portion == null
          ? null
          : await _records.coffeeLot(portion.lotId);
      if (portion == null ||
          lot == null ||
          lot.coffeeId != coffeeId ||
          lot.archivedAtMs != null) {
        throw const StockAdjustmentException('changed');
      }
      final after = reason == 'correction'
          ? grams
          : portion.remainingGrams - grams;
      if (after < -stockTolerance) {
        throw const StockAdjustmentException('insufficient');
      }
      await _checkFrozenAdjustmentCapacity(portion, after);
      await record(
        lot,
        portion.remainingGrams,
        roundStockGrams(after.clamp(0, double.infinity)),
        portion.id,
      );
    } else {
      var lots = await _records.coffeeLots(coffeeId);
      if (lots.isEmpty && reason == 'correction') {
        await _profile.createFirstLot(coffeeId, roastDate: null, grams: null);
        lots = await _records.coffeeLots(coffeeId);
      }
      lots.sort((a, b) {
        final byDate = a.createdAtMs.compareTo(b.createdAtMs);
        return byDate == 0 ? a.id.compareTo(b.id) : byDate;
      });
      final balances = [
        for (final lot in lots)
          lot.remainingGrams == null
              ? null
              : lot.remainingGrams! - (lot.overdrawGrams ?? 0),
      ];
      if (lots.isEmpty || (reason != 'correction' && balances.contains(null))) {
        throw const StockAdjustmentException('unknown');
      }
      if (balances.contains(null)) {
        // A measured total establishes stock without inventing past consumption.
        for (var i = 0; i < lots.length; i++) {
          await record(
            lots[i],
            balances[i],
            i == 0 ? grams : 0,
            null,
            keepUnchanged: true,
          );
        }
      } else {
        final total = balances.fold<double>(0, (sum, value) => sum + value!);
        var delta = reason == 'correction' ? grams - total : -grams;
        if (reason != 'correction' && grams > total + stockTolerance) {
          throw const StockAdjustmentException('insufficient');
        }
        if (delta >= 0) {
          await record(
            lots.first,
            balances.first,
            balances.first! + delta,
            null,
          );
        } else {
          for (var i = 0; i < lots.length && delta < -stockTolerance; i++) {
            final take = min(max(0.0, balances[i]!), -delta);
            if (take == 0) continue;
            await record(lots[i], balances[i], balances[i]! - take, null);
            delta += take;
          }
        }
      }
    }
    await (database.update(database.coffees)
          ..where((r) => r.id.equals(coffeeId)))
        .write(CoffeesCompanion(updatedAtMs: Value(now)));
    return operation;
  });

  Future<void> _checkFrozenAdjustmentCapacity(
    FrozenPortion portion,
    double after,
  ) async {
    final brews = await (database.select(
      database.brews,
    )..where((r) => r.frozenPortionId.equals(portion.id))).get();
    final used = brews
        .where((b) => b.stockReviewPending != true)
        .fold<double>(0, (sum, b) => sum + (b.frozenDoseGrams ?? 0));
    if (after > portion.initialGrams - used + stockTolerance) {
      throw const StockAdjustmentException('capacity');
    }
  }

  Future<void> undoStockAdjustment(String operationId) =>
      database.transaction(() async {
        final rows = await (database.select(
          database.stockAdjustments,
        )..where((r) => r.operationId.equals(operationId))).get();
        if (rows.isEmpty || rows.every((r) => r.reversedAtMs != null)) return;
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        for (final row in rows) {
          if (row.reversedAtMs != null) {
            throw const StockAdjustmentException('changed');
          }
          final owner = await _records.coffee(row.coffeeId);
          final lot = await _records.coffeeLot(row.lotId);
          if (owner == null ||
              owner.archivedAtMs != null ||
              lot == null ||
              lot.archivedAtMs != null) {
            throw const StockAdjustmentException('archived');
          }
          final delta = row.previousGrams == null
              ? null
              : row.resultingGrams - row.previousGrams!;
          if (row.frozenPortionId case final portionId?) {
            final portion = await (database.select(
              database.frozenPortions,
            )..where((r) => r.id.equals(portionId))).getSingle();
            final after = portion.remainingGrams - delta!;
            if (after < -stockTolerance) {
              throw const StockAdjustmentException('changed');
            }
            await _checkFrozenAdjustmentCapacity(portion, after);
            final remaining = roundStockGrams(max(0, after));
            final thawedAt = remaining > stockTolerance
                ? null
                : portion.thawedAtMs ?? now;
            await (database.update(
              database.frozenPortions,
            )..where((r) => r.id.equals(portionId))).write(
              FrozenPortionsCompanion(
                remainingGrams: Value(remaining),
                thawedAtMs: Value(thawedAt),
                updatedAtMs: Value(now),
              ),
            );
          } else {
            final current = lot.remainingGrams == null
                ? null
                : lot.remainingGrams! - (lot.overdrawGrams ?? 0);
            if (current == null ||
                (delta == null &&
                    ((current - row.resultingGrams).abs() > stockTolerance ||
                        lot.updatedAtMs != row.createdAtMs))) {
              throw const StockAdjustmentException('changed');
            }
            final after = delta == null ? null : current - delta;
            if (after != null &&
                delta! > 0 &&
                after < min(0, row.previousGrams!) - stockTolerance) {
              throw const StockAdjustmentException('changed');
            }
            final balance = after == null
                ? (null, null)
                : materializeBalance(after);
            await (database.update(
              database.coffeeLots,
            )..where((r) => r.id.equals(row.lotId))).write(
              CoffeeLotsCompanion(
                remainingGrams: Value(balance.$1),
                overdrawGrams: Value(balance.$2),
                updatedAtMs: Value(now),
              ),
            );
          }
        }
        await (database.update(database.stockAdjustments)
              ..where((r) => r.operationId.equals(operationId)))
            .write(StockAdjustmentsCompanion(reversedAtMs: Value(now)));
      });
}
