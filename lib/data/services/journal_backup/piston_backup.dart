part of '../journal_backup.dart';

class _PistonBackup {
  _PistonBackup(Map<String, dynamic> data)
    : machines = _decode(
        {...data, 'pistonMachines': data['pistonMachines'] ?? <dynamic>[]},
        'pistonMachines',
        PistonMachine.fromJson,
      ),
      links = _decode(
        {
          ...data,
          'pistonMethodLinks': data['pistonMethodLinks'] ?? <dynamic>[],
        },
        'pistonMethodLinks',
        PistonMethodLink.fromJson,
      ),
      readings = _decode(
        {
          ...data,
          'pistonMeasurements': data['pistonMeasurements'] ?? <dynamic>[],
        },
        'pistonMeasurements',
        PistonMeasurement.fromJson,
      ),
      services = _decode(
        {
          ...data,
          'pistonMaintenances': data['pistonMaintenances'] ?? <dynamic>[],
        },
        'pistonMaintenances',
        PistonMaintenance.fromJson,
      );
  final List<PistonMachine> machines;
  final List<PistonMethodLink> links;
  final List<PistonMeasurement> readings;
  final List<PistonMaintenance> services;

  void validate(List<BrewMethod> methods) {
    _ensureUnique(machines.map((r) => r.serial), 'piston machine');
    _ensureUnique(links.map((r) => r.methodId), 'piston method');
    _ensureUnique(
      readings.map((r) => '${r.serial}\u0000${r.shotId}'),
      'piston measurement',
    );
    _ensureUnique(services.map((r) => r.id), 'piston maintenance');
    final serials = machines.map((r) => r.serial).toSet();
    final methodIds = methods.map((r) => r.id).toSet();
    for (final m in machines) {
      if (m.serial.trim().isEmpty ||
          m.serial.length > 200 ||
          (m.cursorMs != null && m.cursorMs! < 0) ||
          (m.checkedAtMs != null && m.checkedAtMs! < 0)) {
        throw const FormatException('Invalid piston machine');
      }
    }
    for (final l in links) {
      if (!serials.contains(l.serial) || !methodIds.contains(l.methodId)) {
        throw const FormatException('Invalid piston method');
      }
    }
    for (final r in readings) {
      if (!serials.contains(r.serial) ||
          r.shotId.isEmpty ||
          r.timeMs < 0 ||
          r.samples < 0 ||
          r.algorithm < 1 ||
          (r.current == null) != (r.speed == null) ||
          (r.current != null &&
              (!r.current!.isFinite ||
                  r.current! < 0 ||
                  !r.speed!.isFinite ||
                  r.speed! < 0 ||
                  r.samples < 5))) {
        throw const FormatException('Invalid piston measurement');
      }
    }
    for (final s in services) {
      if (!serials.contains(s.serial) ||
          s.id.isEmpty ||
          s.timeMs < 0 ||
          !PistonService.kinds.contains(s.kind) ||
          s.notes.length > 2000) {
        throw const FormatException('Invalid piston maintenance');
      }
    }
  }

  Future<void> write(AppDatabase db) => db.batch((b) {
    b.insertAll(db.pistonMachines, machines);
    b.insertAll(db.pistonMethodLinks, links);
    b.insertAll(db.pistonMeasurements, readings);
    b.insertAll(db.pistonMaintenances, services);
  });

  static Future<void> clear(AppDatabase db) async {
    await db.delete(db.pistonMethodLinks).go();
    await db.delete(db.pistonMeasurements).go();
    await db.delete(db.pistonMaintenances).go();
    await db.delete(db.pistonMachines).go();
  }
}
