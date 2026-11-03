import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/domain/remembered_scale.dart';

export 'package:holybeans/domain/remembered_scale.dart';

class ScaleSettings {
  ScaleSettings(this.database);

  final AppDatabase database;

  Future<RememberedScale?> load() async => (await loadAll()).firstOrNull;

  Future<List<RememberedScale>> loadAll() async {
    final row = await database.loadPreferences();
    if (row?.scalesJson case final json?) {
      return RememberedScale.decodeList(json);
    }
    return switch ((row?.scaleDeviceId, row?.scaleName)) {
      (final id?, final name?) => [RememberedScale(deviceId: id, name: name)],
      _ => [],
    };
  }

  // Keep the legacy pair for older readers and backup compatibility.
  Future<void> _write(List<RememberedScale> scales) => database.savePreferences(
    AppPreferencesCompanion(
      scaleDeviceId: Value(scales.firstOrNull?.deviceId),
      scaleName: Value(scales.firstOrNull?.name),
      scalesJson: Value(
        jsonEncode([
          for (final scale in scales)
            {'id': scale.deviceId, 'name': scale.name},
        ]),
      ),
    ),
  );

  /// Moves a successfully connected scale to the front; null forgets all.
  Future<void> save(RememberedScale? scale) =>
      database.writeGate.withPreferencesLock(
        () => database.transaction(() async {
          final previous = await loadAll();
          await _write(
            scale == null
                ? []
                : [
                    scale,
                    ...previous.where(
                      (item) => item.deviceId != scale.deviceId,
                    ),
                  ],
          );
        }),
      );

  Future<void> forget(String id) => database.writeGate.withPreferencesLock(
    () => database.transaction(() async {
      await _write((await loadAll()).where((s) => s.deviceId != id).toList());
    }),
  );
}
