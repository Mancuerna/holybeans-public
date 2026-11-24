import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/equipment_deletion.dart';
import 'package:uuid/uuid.dart';

class PresetDetails {
  const PresetDetails(
    this.preset,
    this.toolIds,
    this.parts,
    this.uses,
    this.available,
  );
  final EquipmentPreset preset;
  final Set<String> toolIds;
  final List<String> parts;
  final int uses;
  final bool available;
}

class EquipmentPresetRepository {
  EquipmentPresetRepository(this.db);
  final AppDatabase db;

  Selectable<QueryRow> _rows({String? id}) => db.customSelect(
    '''
    SELECT p.*, m.name method, g.name grinder, w.name water, t.id tool_id, t.name tool,
      (m.archived_at_ms IS NULL AND g.archived_at_ms IS NULL AND w.archived_at_ms IS NULL
       AND t.archived_at_ms IS NULL AND (t.id IS NULL OR l.tool_id IS NOT NULL)) available,
      (SELECT COUNT(*) FROM brews b WHERE b.equipment_preset_id=p.id) uses
    FROM equipment_presets p JOIN brew_methods m ON m.id=p.method_id
    LEFT JOIN grinders g ON g.id=p.grinder_id LEFT JOIN water_profiles w ON w.id=p.water_profile_id
    LEFT JOIN equipment_preset_tools pt ON pt.preset_id=p.id LEFT JOIN method_tools t ON pt.tool_id=t.id
    LEFT JOIN tool_method_links l ON l.tool_id=t.id AND l.method_id=p.method_id
    ${id == null ? '' : 'WHERE p.id=?'}
    ORDER BY p.name COLLATE NOCASE, p.id, t.name COLLATE NOCASE, t.id
  ''',
    variables: [if (id != null) Variable.withString(id)],
  );

  List<PresetDetails> _details(List<QueryRow> rows) {
    final groups = <String, List<QueryRow>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.read<String>('id'), () => []).add(row);
    }
    return [
      for (final group in groups.values)
        PresetDetails(
          db.equipmentPresets.map(group.first.data),
          {for (final r in group) ?r.readNullable<String>('tool_id')},
          [
            group.first.read<String>('method'),
            ?group.first.readNullable<String>('grinder'),
            for (final r in group) ?r.readNullable<String>('tool'),
            ?group.first.readNullable<String>('water'),
          ],
          group.first.read<int>('uses'),
          group.every((r) => r.read<bool>('available')),
        ),
    ];
  }

  Stream<List<PresetDetails>> watch() => db
      .customSelect(
        'SELECT 1 FROM equipment_presets LIMIT 1',
        readsFrom: {
          db.equipmentPresets,
          db.equipmentPresetTools,
          db.brewMethods,
          db.grinders,
          db.waterProfiles,
          db.methodTools,
          db.toolMethodLinks,
          db.brews,
        },
      )
      .watch()
      .asyncMap(
        (rows) async =>
            rows.isEmpty ? <PresetDetails>[] : _details(await _rows().get()),
      );
  Future<PresetDetails> get(String id) async =>
      _details(await _rows(id: id).get()).single;
  Future<String> create({
    required String name,
    required String methodId,
    String? grinderId,
    String? waterProfileId,
    required Set<String> toolIds,
  }) => db.transaction(() async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw ArgumentError.value(name, 'name');
    }
    final id = const Uuid().v4();
    await db
        .into(db.equipmentPresets)
        .insert(
          EquipmentPreset(
            id: id,
            name: cleanName,
            methodId: methodId,
            grinderId: grinderId,
            waterProfileId: waterProfileId,
          ),
        );
    for (final tool in toolIds) {
      await db
          .into(db.equipmentPresetTools)
          .insert(EquipmentPresetTool(presetId: id, toolId: tool));
    }
    if (!(await get(id)).available) throw StateError('Unavailable equipment');
    return id;
  });

  Future<List<EquipmentDeletionBlocker>> blockers(String id) async =>
      (await get(id)).uses == 0 ? [] : [EquipmentDeletionBlocker.brews];

  Future<void> delete(String id) => db.transaction(() async {
    final found = await blockers(id);
    if (found.isNotEmpty) throw EquipmentInUseException(found);
    await (db.delete(db.equipmentPresets)..where((p) => p.id.equals(id))).go();
  });
}
