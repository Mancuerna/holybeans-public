import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:uuid/uuid.dart';

class PistonSnapshot {
  const PistonSnapshot({
    this.serial,
    this.checkedAtMs,
    this.complete = false,
    this.readings = const [],
    this.services = const [],
  });
  final String? serial;
  final int? checkedAtMs;
  final bool complete;
  final List<PistonReading> readings;
  final List<PistonService> services;
}

class PistonSyncCancelled implements Exception {}

class PistonRepository {
  PistonRepository(this.database);
  final AppDatabase database;
  final Set<String> _syncing = {};

  Future<PistonSnapshot> load(String methodId) =>
      database.transaction(() async {
        final link = await (database.select(
          database.pistonMethodLinks,
        )..where((r) => r.methodId.equals(methodId))).getSingleOrNull();
        if (link == null) return const PistonSnapshot();
        final machine = await (database.select(
          database.pistonMachines,
        )..where((r) => r.serial.equals(link.serial))).getSingle();
        final readings =
            await (database.select(database.pistonMeasurements)
                  ..where((r) => r.serial.equals(link.serial))
                  ..orderBy([(r) => OrderingTerm.asc(r.timeMs)]))
                .get();
        final services =
            await (database.select(database.pistonMaintenances)
                  ..where((r) => r.serial.equals(link.serial))
                  ..orderBy([(r) => OrderingTerm.asc(r.timeMs)]))
                .get();
        return PistonSnapshot(
          serial: link.serial,
          checkedAtMs: machine.checkedAtMs,
          complete: machine.complete,
          readings: List.unmodifiable(
            readings.map(
              (r) => PistonReading(
                shotId: r.shotId,
                timeMs: r.timeMs,
                samples: r.samples,
                current: r.current,
                speed: r.speed,
              ),
            ),
          ),
          services: List.unmodifiable(
            services.map(
              (r) => PistonService(
                id: r.id,
                timeMs: r.timeMs,
                kind: r.kind,
                notes: r.notes,
              ),
            ),
          ),
        );
      });

  Future<void> sync(
    String methodId,
    PistonHistorySource source, {
    required bool Function() cancelled,
    required void Function(int) onProgress,
  }) async {
    void check() {
      if (cancelled()) throw PistonSyncCancelled();
    }

    String? locked;
    try {
      final serial = await source.serial();
      check();
      if (!_syncing.add(serial)) throw StateError('Machine already updating');
      locked = serial;
      await database.transaction(() async {
        await database
            .into(database.pistonMachines)
            .insert(
              PistonMachinesCompanion.insert(serial: serial),
              mode: InsertMode.insertOrIgnore,
            );
        await database
            .into(database.pistonMethodLinks)
            .insertOnConflictUpdate(
              PistonMethodLinksCompanion.insert(
                methodId: methodId,
                serial: serial,
              ),
            );
      });
      final machine = await (database.select(
        database.pistonMachines,
      )..where((r) => r.serial.equals(serial))).getSingle();
      final existing = await (database.select(
        database.pistonMeasurements,
      )..where((r) => r.serial.equals(serial))).get();
      final known = {
        for (final r in existing)
          if (r.algorithm == pistonAlgorithmVersion) r.shotId,
      };
      var cursor = existing.any((r) => r.algorithm != pistonAlgorithmVersion)
          ? null
          : machine.cursorMs;
      var limit = 128;
      var processed = 0;
      while (true) {
        check();
        final since = cursor == null ? null : math.max(0, cursor - 1000);
        final page = await source.index(sinceMs: since, limit: limit);
        check();
        if (page.length > limit ||
            page.any((p) => since != null && p.timeMs < since - 1)) {
          throw const FormatException('History ignored its bounds');
        }
        final ids = page
            .map((r) => r.id)
            .toSet()
            .where((id) => !known.contains(id))
            .toList();
        for (var offset = 0; offset < ids.length; offset += 10) {
          check();
          final batch = ids.sublist(offset, math.min(offset + 10, ids.length));
          final rows = await source.readings(batch);
          check();
          if (rows.length != batch.length ||
              rows.map((r) => r.shotId).toSet().length != batch.length ||
              !rows.every((r) => batch.contains(r.shotId))) {
            throw const FormatException('Incomplete history');
          }
          await database.transaction(() async {
            await database.batch((b) {
              for (final r in rows) {
                b.insert(
                  database.pistonMeasurements,
                  PistonMeasurementsCompanion.insert(
                    serial: serial,
                    shotId: r.shotId,
                    timeMs: r.timeMs,
                    samples: r.samples,
                    current: Value(r.current),
                    speed: Value(r.speed),
                    algorithm: pistonAlgorithmVersion,
                  ),
                  mode: InsertMode.insertOrReplace,
                );
              }
            });
          });
          known.addAll(batch);
          processed += rows.length;
          onProgress(processed);
        }
        // Advance only after the entire index page has been read successfully.
        final next = page.isEmpty ? cursor : page.last.timeMs;
        await (database.update(
          database.pistonMachines,
        )..where((r) => r.serial.equals(serial))).write(
          PistonMachinesCompanion(
            cursorMs: Value(next),
            complete: Value(page.length < limit || machine.complete),
            checkedAtMs: page.length < limit
                ? Value(DateTime.now().millisecondsSinceEpoch)
                : const Value.absent(),
          ),
        );
        if (page.length < limit) break;
        if (next == cursor) {
          if (limit >= 8192) {
            throw const FormatException('Too many shots at one timestamp');
          }
          limit *= 2;
        } else {
          limit = 128;
        }
        cursor = next;
      }
    } finally {
      if (locked != null) _syncing.remove(locked);
      source.close();
    }
  }

  Future<void> saveService(String serial, PistonService service) async {
    if (!PistonService.kinds.contains(service.kind) ||
        service.timeMs < 0 ||
        service.timeMs > DateTime.now().millisecondsSinceEpoch ||
        service.notes.length > 2000) {
      throw const FormatException('Invalid maintenance');
    }
    await database
        .into(database.pistonMaintenances)
        .insertOnConflictUpdate(
          PistonMaintenancesCompanion.insert(
            id: service.id.isEmpty ? const Uuid().v4() : service.id,
            serial: serial,
            timeMs: service.timeMs,
            kind: service.kind,
            notes: service.notes.trim(),
          ),
        );
  }

  Future<void> deleteService(String serial, String id) => (database.delete(
    database.pistonMaintenances,
  )..where((r) => r.serial.equals(serial) & r.id.equals(id))).go();
}
