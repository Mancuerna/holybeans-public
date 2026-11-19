part of '../journal_backup.dart';

extension on _RestoredJournal {
  void _checkAdjustments() {
    _ensureUnique(adjustments.map((r) => r.id), 'stock adjustments');
    final groups = <String, StockAdjustment>{};
    final coffeesById = {for (final c in coffees) c.id: c};
    final blendSources = <String, Set<String>>{};
    final usedLots = <(String, String)>{};
    for (final row in adjustments) {
      final lot = _lotsById[row.lotId];
      final portion = frozenPortions
          .where((p) => p.id == row.frozenPortionId)
          .firstOrNull;
      final previous = row.previousGrams;
      final target = _lotsById[row.blendLotId];
      if (row.reason == 'blend') {
        if ((row.sourceRoastDate != null &&
                DateTime.tryParse(row.sourceRoastDate!) == null) ||
            target == null ||
            coffeesById[target.coffeeId]?.mixedAtMs == null ||
            coffeesById[row.coffeeId]?.mixedAtMs != null ||
            row.frozenPortionId != null ||
            row.reversedAtMs != null ||
            row.resultingGrams < 0 ||
            !usedLots.add((target.id, row.lotId))) {
          throw const FormatException('Invalid blend contribution');
        }
        (blendSources[target.coffeeId] ??= {}).add(row.coffeeId);
      } else if (row.blendLotId != null || row.sourceRoastDate != null) {
        throw const FormatException('Unexpected blend contribution');
      }
      if (row.id.isEmpty ||
          row.operationId.isEmpty ||
          lot == null ||
          lot.coffeeId != row.coffeeId ||
          (row.frozenPortionId != null &&
              (portion == null || portion.lotId != row.lotId)) ||
          !{'gift', 'waste', 'correction', 'blend'}.contains(row.reason) ||
          !row.resultingGrams.isFinite ||
          (previous != null && !previous.isFinite) ||
          (row.reason != 'correction' &&
              (previous == null || row.resultingGrams >= previous)) ||
          (row.frozenPortionId != null &&
              (previous == null || previous < 0 || row.resultingGrams < 0)) ||
          (row.notes?.length ?? 0) > 500 ||
          row.createdAtMs < 0 ||
          (row.reversedAtMs != null && row.reversedAtMs! < row.createdAtMs)) {
        throw const FormatException('Invalid stock adjustment');
      }
      final first = groups.putIfAbsent(row.operationId, () => row);
      if (first.coffeeId != row.coffeeId ||
          first.reason != row.reason ||
          first.notes != row.notes ||
          first.createdAtMs != row.createdAtMs ||
          first.reversedAtMs != row.reversedAtMs) {
        throw const FormatException('Inconsistent stock adjustment operation');
      }
    }
    for (final coffee in coffees.where((c) => c.mixedAtMs != null)) {
      if ((blendSources[coffee.id]?.length ?? 0) < 2) {
        throw const FormatException('Missing blend sources');
      }
    }
    _ensureUnique(
      adjustments.map(
        (r) => '${r.operationId}:${r.lotId}:${r.frozenPortionId}',
      ),
      'stock adjustment allocations',
    );
  }
}
