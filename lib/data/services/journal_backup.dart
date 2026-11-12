import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/data/services/journal_lock.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/brix.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';
import 'package:holybeans/domain/remembered_scale.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/domain/water_chemistry.dart';

part 'journal_backup/backup_rows.dart';
part 'journal_backup/cafe_backup.dart';
part 'journal_backup/piston_backup.dart';
part 'journal_backup/restored_journal.dart';

/// Versioned, portable JSON for HolyBeans data. The file picker and sharing UI
/// can use this service without knowing how records are stored in SQLite.
class JournalBackup {
  JournalBackup(this.database);

  static const format = 'holybeans-backup';

  /// Fires after any write to the journal, so automatic copies know when
  /// there is something new to save.
  Stream<void> watchChanges() => database.tableUpdates().map((_) {});
  static const version = 37;

  /// Name of the journal inside a ZIP backup; photos go under `photos/`.
  static const archiveJournal = 'holybeans-backup.json';
  static const _archivePhotos = 'photos/';

  /// Versions 5 and 6 predate frozen portions (v5), grinder RPM and the
  /// newer brew measurements; they are still accepted. Up to v15 a coffee or
  /// brew had a single `photoFile`, read as its first photo. v16 kept a
  /// catalog of vessels, now ignored: the jug belongs to its method. Up to
  /// v30 a brew saved before the jug catalog may have lost its jug; restoring
  /// one gives it back (see `restoreLegacyBrewRecipients`).
  static const _readableVersions = {
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
  };
  static const _collections = {
    'extractionProfiles',
    'pistonMachines',
    'pistonMethodLinks',
    'pistonMeasurements',
    'pistonMaintenances',
    'roasters',
    'coffeeRoasterLinks',
    'cafes',
    'cafeDrinks',
    'cafeDrinkPhotos',

    'recipients',
    'stockAdjustments',
    'coffees',
    'components',
    'lots',
    'frozenPortions',
    'methods',
    'grinders',
    'waterProfiles',
    // v16 only; read and ignored.
    'vessels',
    'methodTools',
    'toolMethodLinks',
    'brews',
    'brewToolSelections',
    'brewCurves',
    'coffeePhotos',
    'brewPhotos',
    'importRecords',
    'legacyPayloads',
    'preferences',
    'cuppingSessions',
    'cuppingSessionCups',
  };

  final AppDatabase database;

  /// Counts records before a restore so the UI can explain what will replace
  /// the current journal. Full row validation is performed by [prepareRestore].
  static BackupSummary inspectJson(String source) {
    final (:data, version: _) = _readBackup(source);
    int count(String key) {
      final value = data[key];
      if (value is! List) {
        throw FormatException('Missing backup collection: $key');
      }
      return value.length;
    }

    int optionalCount(String key) {
      final value = data[key];
      if (value == null) return 0;
      if (value is! List) {
        throw FormatException('Invalid backup collection: $key');
      }
      return value.length;
    }

    return BackupSummary(
      cafeDrinks: optionalCount('cafeDrinks'),
      cafes: optionalCount('cafes'),
      cuppingSessions: optionalCount('cuppingSessions'),
      coffees: count('coffees'),
      components: count('components'),
      lots: count('lots'),
      frozenPortions: optionalCount('frozenPortions'),
      methods: count('methods'),
      grinders: count('grinders'),
      waterProfiles: optionalCount('waterProfiles'),
      methodTools: count('methodTools'),
      brews: count('brews'),
      brewToolSelections: count('brewToolSelections'),
      importRecords: count('importRecords'),
      legacyPayloads: count('legacyPayloads'),
    );
  }

  /// Counts backup records in a worker before asking to replace the journal.
  static Future<BackupSummary> inspectJsonInBackground(String source) =>
      Isolate.run(() => inspectJson(source));

  /// Reads a ZIP or legacy JSON backup once and prepares its preview in a worker.
  ///
  /// If [archiveOnly] is true, legacy JSON inputs are rejected.
  static Future<BackupContents> readInBackground(
    Uint8List bytes, {
    bool archiveOnly = false,
  }) => Isolate.run(() {
    final isZip =
        archiveOnly ||
        (bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B);
    final (source, files) = isZip
        ? readArchive(bytes)
        : (utf8.decode(bytes), <String, Uint8List>{});
    return BackupContents._(source, files, inspectJson(source));
  });

  Future<String> exportJson() async => jsonEncode(await _exportData());

  Future<String> exportJsonInBackground() async {
    final data = await _exportData();
    return Isolate.run(() => jsonEncode(data));
  }

  Future<Map<String, Object>> _exportData() => database.transaction(() async {
    final data = <String, Object>{
      'roasters': await _encode(
        database.select(database.roasters).get(),
        (Roaster r) => r.id,
        (Roaster r) => r.toJson(),
      ),
      'coffeeRoasterLinks': await _encode(
        database.select(database.coffeeRoasterLinks).get(),
        (CoffeeRoasterLink r) => r.coffeeId,
        (CoffeeRoasterLink r) => r.toJson(),
      ),
      'cafes': await _encode(
        database.select(database.cafes).get(),
        (Cafe r) => r.id,
        (Cafe r) => r.toJson(),
      ),
      'cafeDrinks': await _encode(
        database.select(database.cafeDrinks).get(),
        (CafeDrink r) => r.id,
        (CafeDrink r) => r.toJson(),
      ),
      'cafeDrinkPhotos': await _encode(
        database.select(database.cafeDrinkPhotos).get(),
        (CafeDrinkPhoto r) => _photoKey(r.drinkId, r.position),
        (CafeDrinkPhoto r) => r.toJson(),
      ),

      'pistonMachines': await _encode(
        database.select(database.pistonMachines).get(),
        (PistonMachine r) => r.serial,
        (PistonMachine r) => r.toJson(),
      ),
      'pistonMethodLinks': await _encode(
        database.select(database.pistonMethodLinks).get(),
        (PistonMethodLink r) => r.methodId,
        (PistonMethodLink r) => r.toJson(),
      ),
      'pistonMeasurements': await _encode(
        database.select(database.pistonMeasurements).get(),
        (PistonMeasurement r) => '${r.serial}\u0000${r.shotId}',
        (PistonMeasurement r) => r.toJson(),
      ),
      'pistonMaintenances': await _encode(
        database.select(database.pistonMaintenances).get(),
        (PistonMaintenance r) => r.id,
        (PistonMaintenance r) => r.toJson(),
      ),
      'recipients': await _encode(
        database.select(database.recipients).get(),
        (Recipient r) => r.id,
        (Recipient r) => r.toJson(),
      ),
      'stockAdjustments': await _encode(
        database.select(database.stockAdjustments).get(),
        (StockAdjustment row) => row.id,
        (StockAdjustment row) => row.toJson(),
      ),
      'cuppingSessions': await _encode(
        database.select(database.cuppingSessions).get(),
        (CuppingSession row) => row.id,
        (CuppingSession row) => row.toJson(),
      ),
      'cuppingSessionCups': await _encode(
        database.select(database.cuppingSessionCups).get(),
        (CuppingSessionCup row) => row.id,
        (CuppingSessionCup row) => row.toJson(),
      ),
      'coffees': await _encode(
        database.select(database.coffees).get(),
        (Coffee value) => value.id,
        (Coffee value) => value.toJson(),
      ),
      'components': await _encode(
        database.select(database.coffeeComponents).get(),
        (CoffeeComponent value) => value.id,
        (CoffeeComponent value) => value.toJson(),
      ),
      'lots': await _encode(
        database.select(database.coffeeLots).get(),
        (CoffeeLot value) => value.id,
        (CoffeeLot value) => value.toJson(),
      ),
      'frozenPortions': await _encode(
        database.select(database.frozenPortions).get(),
        (FrozenPortion value) => value.id,
        (FrozenPortion value) => value.toJson(),
      ),
      'methods': await _encode(
        database.select(database.brewMethods).get(),
        (BrewMethod value) => value.id,
        (BrewMethod value) => value.toJson(),
      ),
      'grinders': await _encode(
        database.select(database.grinders).get(),
        (Grinder value) => value.id,
        (Grinder value) => value.toJson(),
      ),
      'waterProfiles': await _encode(
        database.select(database.waterProfiles).get(),
        (WaterProfile value) => value.id,
        (WaterProfile value) => value.toJson(),
      ),
      'methodTools': await _encode(
        database.select(database.methodTools).get(),
        (MethodTool value) => value.id,
        (MethodTool value) => value.toJson(),
      ),
      'toolMethodLinks': await _encode(
        database.select(database.toolMethodLinks).get(),
        (ToolMethodLink value) => '${value.toolId}\u0000${value.methodId}',
        (ToolMethodLink value) => value.toJson(),
      ),
      'brews': await _encode(
        database.select(database.brews).get(),
        (Brew value) => value.id,
        (Brew value) => value.toJson(),
      ),
      'brewCurves': await _encode(
        database.select(database.brewCurves).get(),
        (BrewCurve value) => value.brewId,
        (BrewCurve value) => value.toJson(),
      ),
      'coffeePhotos': await _encode(
        database.select(database.coffeePhotos).get(),
        (CoffeePhoto value) => _photoKey(value.coffeeId, value.position),
        (CoffeePhoto value) => value.toJson(),
      ),
      'brewPhotos': await _encode(
        database.select(database.brewPhotos).get(),
        (BrewPhoto value) => _photoKey(value.brewId, value.position),
        (BrewPhoto value) => value.toJson(),
      ),
      'brewToolSelections': await _encode(
        database.select(database.brewToolSelections).get(),
        (BrewToolSelection value) => '${value.brewId}\u0000${value.toolId}',
        (BrewToolSelection value) => value.toJson(),
      ),
      'importRecords': await _encode(
        database.select(database.importRecords).get(),
        (ImportRecord value) => value.id,
        (ImportRecord value) => value.toJson(),
      ),
      'legacyPayloads': await _encode(
        database.select(database.legacyPayloads).get(),
        (LegacyPayload value) => value.importRecordId,
        (LegacyPayload value) => value.toJson(),
      ),
      'extractionProfiles': await _encode(
        database.select(database.extractionProfiles).get(),
        (ExtractionProfileRow r) => r.id,
        (ExtractionProfileRow r) => r.toJson(),
      ),
      'preferences': await _encode(
        database.select(database.appPreferences).get(),
        (AppPreference value) => value.id.toString(),
        (AppPreference value) => value.toJson(),
      ),
    };
    return {
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
  });

  /// Replaces the local journal atomically. The caller must request explicit
  /// confirmation in the UI before using this destructive operation.
  ///
  /// Photo references are kept only when their file is in [availablePhotos];
  /// a plain JSON backup carries no photos, so its references are cleared.
  Future<BackupSummary> restoreJson(
    String source, {
    Set<String> availablePhotos = const {},
  }) async => restorePrepared(
    await prepareRestore(source, availablePhotos: availablePhotos),
  );

  /// Decodes and validates rows in a worker without writing the journal.
  ///
  /// Photo references are selected from a snapshot of [availablePhotos].
  static Future<PreparedBackup> prepareRestore(
    String source, {
    Set<String> availablePhotos = const {},
  }) {
    final available = Set<String>.of(availablePhotos);
    return Isolate.run(
      () => PreparedBackup._(_validatedJournal(source, available.contains)),
    );
  }

  /// Applies rows already checked by [prepareRestore] in one transaction.
  ///
  /// The caller must obtain explicit confirmation as required by [restoreJson].
  Future<BackupSummary> restorePrepared(PreparedBackup prepared) async {
    await prepared._journal.replace(database);
    return prepared.summary;
  }

  /// Checks every backup row and relation without changing the journal.
  ///
  /// [keepPhoto] selects photo references whose files will be available.
  static void validate(String source, bool Function(String) keepPhoto) {
    _validatedJournal(source, keepPhoto);
  }

  static _RestoredJournal _validatedJournal(
    String source,
    bool Function(String) keepPhoto,
  ) {
    final (:data, :version) = _readBackup(source);
    return _RestoredJournal.decode(
      data,
      restoreBrewJugs: version <= 30,
      keepPhoto: (name) {
        if (!PhotoStore.isValidName(name)) {
          throw const FormatException('Backup has an invalid photo name');
        }
        return keepPhoto(name);
      },
    )..validate();
  }

  /// Exports the journal and its photos with JSON and ZIP encoding in workers.
  Future<Uint8List> exportArchive(PhotoStore? photos) =>
      JournalLock.withJournalLock(
        photos,
        () => database.transaction(() async {
          final source = await exportJsonInBackground();
          final files = await referencedPhotos(photos);
          return _encodeArchiveInBackground(source, files);
        }),
      );

  /// Reads only the stored photos the journal references, by name.
  Future<Map<String, Uint8List>> referencedPhotos(PhotoStore? photos) async {
    if (photos == null) return const {};
    final referenced = {
      for (final photo in await database.select(database.cafeDrinkPhotos).get())
        photo.fileName,
      for (final photo in await database.select(database.coffeePhotos).get())
        photo.fileName,
      for (final photo in await database.select(database.brewPhotos).get())
        photo.fileName,
    };
    final stored = <String, Uint8List>{};
    for (final name in referenced) {
      if (!PhotoStore.isValidName(name)) continue;
      final file = photos.file(name);
      if (file.existsSync()) stored[name] = await file.readAsBytes();
    }
    return stored;
  }

  static Future<Uint8List> _encodeArchiveInBackground(
    String source,
    Map<String, Uint8List> photos,
  ) => Isolate.run(() => encodeArchive(source, photos));

  /// A ZIP with the journal [source] and [photos]. Pure, so it can run in
  /// another isolate.
  static Uint8List encodeArchive(String source, Map<String, Uint8List> photos) {
    final archive = Archive()
      ..add(ArchiveFile.bytes(archiveJournal, utf8.encode(source)));
    for (final entry in photos.entries) {
      archive.add(
        ArchiveFile.bytes('$_archivePhotos${entry.key}', entry.value),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Reads a ZIP backup into its journal source and valid photos.
  static (String, Map<String, Uint8List>) readArchive(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Unsupported HolyBeans backup');
    }
    final journal = archive.find(archiveJournal)?.readBytes();
    if (journal == null) {
      throw const FormatException('Missing HolyBeans journal');
    }
    final photos = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile || !file.name.startsWith(_archivePhotos)) continue;
      final name = file.name.substring(_archivePhotos.length);
      final content = file.readBytes();
      // Unexpected names (including paths) are ignored, never written.
      if (PhotoStore.isValidName(name) && content != null) {
        photos[name] = content;
      }
    }
    return (utf8.decode(journal), photos);
  }

  static BackupSummary inspectArchive(Uint8List bytes) =>
      inspectJson(readArchive(bytes).$1);
}

/// A decoded backup and its preview, retained while the user confirms a restore.
class BackupContents {
  BackupContents._(this.source, Map<String, Uint8List> photos, this.summary)
    : photos = Map.unmodifiable(photos);

  final String source;
  final Map<String, Uint8List> photos;
  final BackupSummary summary;
}

/// Validated backup rows ready to apply without decoding or validating again.
class PreparedBackup {
  PreparedBackup._(this._journal);

  final _RestoredJournal _journal;
  BackupSummary get summary => _journal.summary;
}

class BackupSummary {
  const BackupSummary({
    this.cuppingSessions = 0,
    this.cafeDrinks = 0,
    this.cafes = 0,
    required this.coffees,
    required this.components,
    required this.lots,
    required this.frozenPortions,
    required this.methods,
    required this.grinders,
    required this.waterProfiles,
    required this.methodTools,
    required this.brews,
    required this.brewToolSelections,
    required this.importRecords,
    required this.legacyPayloads,
  });

  final int cafeDrinks;
  final int cafes;
  final int cuppingSessions;
  final int coffees;
  final int components;
  final int lots;
  final int frozenPortions;
  final int methods;
  final int grinders;
  final int waterProfiles;
  final int methodTools;
  final int brews;
  final int brewToolSelections;
  final int importRecords;
  final int legacyPayloads;
}
